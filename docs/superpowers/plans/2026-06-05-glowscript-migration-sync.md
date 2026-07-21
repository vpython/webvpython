# GlowScript Migration Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring rsWVPRunner, wmWVPRunner, and flaskHost up to date with Classic GlowScript so the new setup can replace Classic in production.

**Architecture:** Three independent phases, each fully committable before the next begins. rsWVPRunner gets two file copies; wmWVPRunner gets a branch merge and build fix; flaskHost gets a security upgrade, new DB methods, and ported analytics routes.

**Tech Stack:** Python/Flask (flaskHost), SvelteKit/Pyodide (wmWVPRunner), static JS (rsWVPRunner), MongoDB/bunnet (flaskHost DB layer), pytest (tests)

---

## Task 1: rsWVPRunner — Sync lib/glow files

**Files:**
- Modify: `rsWVPRunner/lib/glow/extrude.js`
- Modify: `rsWVPRunner/lib/glow/primitives.js`

- [ ] **Step 1: Copy updated files from Classic**

```bash
cp glowscript/lib/glow/extrude.js rsWVPRunner/lib/glow/extrude.js
cp glowscript/lib/glow/primitives.js rsWVPRunner/lib/glow/primitives.js
```

- [ ] **Step 2: Verify files are now identical to Classic**

```bash
diff glowscript/lib/glow/extrude.js rsWVPRunner/lib/glow/extrude.js
diff glowscript/lib/glow/primitives.js rsWVPRunner/lib/glow/primitives.js
```

Expected: no output from either diff.

- [ ] **Step 3: Commit**

```bash
cd rsWVPRunner
git add lib/glow/extrude.js lib/glow/primitives.js
git commit -m "sync: update lib/glow/extrude.js and primitives.js from Classic GlowScript"
```

---

## Task 2: wmWVPRunner — Merge Pyodide upgrade and fix build

**Files:**
- Modify: `wmWVPRunner/do_build.sh`
- Modify: `wmWVPRunner/.gitignore`
- Delete: `wmWVPRunner/static/vpython.zip` (from git tracking)
- Modify: `wmWVPRunner/CLAUDE.md`

- [ ] **Step 1: Merge the upgrade branch**

```bash
cd wmWVPRunner
git merge upgrade-pyodide-v0.29.4
```

Expected: fast-forward or merge commit. If there are conflicts, resolve by keeping the upgrade branch version of any Pyodide version strings.

- [ ] **Step 2: Remove vpython.zip from git tracking and add to .gitignore**

`static/vpython.zip` is a generated binary that should not be in version control — it gets built by `npm run zip` before each deploy.

```bash
git rm --cached static/vpython.zip
```

Open `wmWVPRunner/.gitignore` and add this line at the end:
```
static/vpython.zip
```

- [ ] **Step 3: Update do_build.sh to build vpython.zip before the SvelteKit build**

Open `wmWVPRunner/do_build.sh`. After the `set -e` line and before the `echo "=== Starting build and deploy ==="` line, add:

```bash
# Build the vpython Python package zip from source
echo "Building vpython.zip..."
npm run zip
```

The relevant section should look like this after the change:
```bash
#!/bin/bash
set -e  # Exit on error

# Build the vpython Python package zip from source
echo "Building vpython.zip..."
npm run zip

export GSUTIL_OPTS="-o GSUtil:parallel_process_count=1"

echo "=== Starting build and deploy ==="
```

- [ ] **Step 4: Verify the build works end-to-end**

```bash
npm run zip && npm run build
ls -lh build/vpython.zip
```

Expected: `build/vpython.zip` is present, nonzero size.

- [ ] **Step 5: Update CLAUDE.md to reflect new Pyodide version and build step**

In `wmWVPRunner/CLAUDE.md`, find the `## Solution` section and update the Pyodide version reference from `v0.23.3` to `v0.29.4`. Also update the `## Build and Deployment` section to document the `npm run zip` pre-step.

In the `## Build and Deployment` section, replace the existing code block with:

```bash
# Build vpython package first
npm run zip

# Clean old artifacts
gcloud storage rm -r gs://wmvprunner/_app/ 2>/dev/null || true
gcloud storage rm gs://wmvprunner/index.html gs://wmvprunner/favicon.png 2>/dev/null || true

# Set CORS on bucket
gcloud storage buckets update gs://wmvprunner --cors-file=cors.json

# Build the app (vpython.zip lands in build/ via static/)
npm run build

# Upload with cache headers
gcloud storage cp -r build/* gs://wmvprunner/ --cache-control="public, max-age=3600"

# Set proper content types and no-cache for index
gcloud storage objects update gs://wmvprunner/index.html \
  --cache-control="no-cache, no-store, must-revalidate"
gcloud storage objects update gs://wmvprunner/vpython.zip \
  --content-type=application/zip --cache-control=no-cache
```

- [ ] **Step 6: Commit**

```bash
cd wmWVPRunner
git add do_build.sh .gitignore CLAUDE.md
git commit -m "feat: merge Pyodide v0.29.4 upgrade, build vpython.zip from source in deploy step"
```

---

## Task 3: flaskHost — Update dependencies and Dockerfile

**Files:**
- Modify: `flaskHost/requirements.txt`
- Modify: `flaskHost/Dockerfile`

- [ ] **Step 1: Update Authlib (critical security fix) and key dependencies**

Open `flaskHost/requirements.txt` and update these lines:

```
Authlib==1.6.7
cryptography==46.0.7
Flask==2.3.2
google-auth==2.40.3
google-cloud-datastore==2.23.0
google-cloud-ndb==2.4.0
Jinja2==3.1.6
python-dotenv==1.2.2
requests==2.33.0
Werkzeug==3.0.1
```

Keep all other lines (MongoDB-specific packages, pytest, etc.) unchanged. The Authlib upgrade fixes CVE-2026-28802 (JWT alg:none bypass).

- [ ] **Step 2: Update Dockerfile to Python 3.12**

Open `flaskHost/Dockerfile`. Change the first line from:
```
FROM python:3.10-slim
```
to:
```
FROM python:3.12-slim
```

- [ ] **Step 3: Verify pip install succeeds**

```bash
cd flaskHost
pip install -r requirements.txt --dry-run 2>&1 | tail -5
```

Expected: no dependency conflicts. If conflicts appear, check which package version introduced them and adjust.

- [ ] **Step 4: Commit**

```bash
cd flaskHost
git add requirements.txt Dockerfile
git commit -m "security: upgrade Authlib to 1.6.7 (CVE-2026-28802), bump Python to 3.12"
```

---

## Task 4: flaskHost — Add Setting model and DB layer methods

The `/plotusers` and `/admin/update-user-count` routes need to read and write a user-count history document, and count active users. These require three new methods on the DB abstraction layer and a new MongoDB `Setting` model.

**Files:**
- Modify: `flaskHost/src/mongo_models.py`
- Modify: `flaskHost/src/db_translate.py`

- [ ] **Step 1: Add Setting document model to mongo_models.py**

Open `flaskHost/src/mongo_models.py`. Add `Setting` to the document models, and update `init_client` to register it.

After the existing imports and before `def init_client(...)`, the file already has `User`, `Folder`, `Program`. Add `Setting` after `Program`:

```python
class Setting(Document):
    """Key-value settings store"""
    key: Indexed(str, unique=True)
    value: str = 'NOT SET'
```

Update `init_client` to include `Setting`:

```python
def init_client(MONGO_URL):
    client = MongoClient(MONGO_URL)
    init_bunnet(database=client.gldb, document_models=[User, Folder, Program, Setting])
    return client
```

- [ ] **Step 2: Add abstract methods to DBGlue**

Open `flaskHost/src/db_translate.py`. Add three abstract methods to `DBGlue` after `set_datetime`:

```python
    @abc.abstractmethod
    def count_users(self):
        """Return the current number of User records."""
        pass

    @abc.abstractmethod
    def get_setting(self, key):
        """Return the value string for the given setting key, or None if not set."""
        pass

    @abc.abstractmethod
    def set_setting(self, key, value):
        """Persist value string for the given setting key (upsert)."""
        pass
```

- [ ] **Step 3: Implement methods in NDB_DBGlue**

Add to `NDB_DBGlue` in `db_translate.py`, after `set_datetime`:

```python
    def count_users(self):
        from google.cloud import datastore
        ds_client = datastore.Client()
        stat = ds_client.get(ds_client.key('__Stat_Kind__', 'User'))
        return stat['count'] if stat else 0

    def get_setting(self, key):
        setting = ndb_models.ndb.Key('Setting', key).get()
        if not setting or setting.value == 'NOT SET':
            return None
        return setting.value

    def set_setting(self, key, value):
        setting = ndb_models.ndb.Key('Setting', key).get()
        if not setting:
            setting = ndb_models.Setting(id=key)
        setting.value = value
        setting.put()
```

- [ ] **Step 4: Implement methods in MONGO_DBGlue**

Add to `MONGO_DBGlue` in `db_translate.py`, after `set_datetime`:

```python
    def count_users(self):
        return self.client.gldb['User'].count_documents({})

    def get_setting(self, key):
        setting = mongo_models.Setting.find({"key": key}).first_or_none()
        if not setting or setting.value == 'NOT SET':
            return None
        return setting.value

    def set_setting(self, key, value):
        setting = mongo_models.Setting.find({"key": key}).first_or_none()
        if not setting:
            setting = mongo_models.Setting(key=key, value=value)
            setting.insert()
        else:
            setting.value = value
            setting.save()
```

- [ ] **Step 5: Commit**

```bash
cd flaskHost
git add src/mongo_models.py src/db_translate.py
git commit -m "feat: add Setting model and count_users/get_setting/set_setting to DB layer"
```

---

## Task 5: flaskHost — Write failing tests for plotusers routes

**Files:**
- Create: `flaskHost/tests/__init__.py`
- Create: `flaskHost/tests/conftest.py`
- Create: `flaskHost/tests/test_plotusers.py`

- [ ] **Step 1: Create test package files**

Create `flaskHost/tests/__init__.py` as an empty file:
```bash
touch flaskHost/tests/__init__.py
```

Create `flaskHost/tests/conftest.py`:

```python
import pytest
from unittest.mock import MagicMock, patch
from main import app as flask_app


@pytest.fixture
def app():
    with patch('src.auth.GRL', True), \
         patch('google.cloud.ndb.Client', return_value=MagicMock()):
        flask_app.config.update({"TESTING": True})
        yield flask_app


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture(autouse=True)
def mock_auth(mocker):
    mocker.patch('src.auth.is_logged_in', return_value=False)
    mocker.patch('src.auth.get_user_info', return_value=None)
```

- [ ] **Step 2: Write failing tests for /plotusers and /admin/update-user-count**

Create `flaskHost/tests/test_plotusers.py`:

```python
import json
from unittest.mock import patch, MagicMock


def test_plotusers_no_history(client, mocker):
    """Returns 200 with a no-data message when no history exists."""
    mocker.patch('src.routes.db.get_setting', return_value=None)
    response = client.get('/plotusers')
    assert response.status_code == 200
    assert b'no data' in response.data.lower()


def test_plotusers_with_history(client, mocker):
    """Returns 200 and embeds the points JSON and updated date."""
    points = [
        {'month': '2012-09', 'count': 320},
        {'month': '2026-05', 'count': 314925},
    ]
    history = json.dumps({'updated': '2026-05-20', 'points': points})
    mocker.patch('src.routes.db.get_setting', return_value=history)

    response = client.get('/plotusers')

    assert response.status_code == 200
    assert b'314925' in response.data
    assert b'2026-05-20' in response.data


def test_plotusers_loads_local_plotly(client, mocker):
    """Template references the local plotlyVP7.min.js, not a CDN."""
    mocker.patch('src.routes.db.get_setting', return_value=None)
    response = client.get('/plotusers')
    assert b'plotlyVP7.min.js' in response.data


def test_update_user_count_no_auth_header(client):
    """Returns 403 when Authorization header is absent."""
    response = client.get('/admin/update-user-count')
    assert response.status_code == 403


def test_update_user_count_appends_new_point(client, mocker):
    """Appends a new data point to existing history and returns 200."""
    existing = {
        'updated': '2026-04-01',
        'points': [{'month': '2012-09', 'count': 320}],
    }
    mocker.patch('src.routes.db.count_users', return_value=314925)
    mocker.patch('src.routes.db.get_setting', return_value=json.dumps(existing))
    set_mock = mocker.patch('src.routes.db.set_setting')

    mock_claim = {'email': 'test-sa@example.iam.gserviceaccount.com'}
    with patch('src.routes._SCHEDULER_SA', 'test-sa@example.iam.gserviceaccount.com'), \
         patch('src.routes._SCHEDULER_AUDIENCE', 'https://example.com/admin/update-user-count'), \
         patch('google.oauth2.id_token.verify_oauth2_token', return_value=mock_claim):
        response = client.get(
            '/admin/update-user-count',
            headers={'Authorization': 'Bearer faketoken'}
        )

    assert response.status_code == 200
    _key, written_value = set_mock.call_args[0]
    written = json.loads(written_value)
    assert len(written['points']) == 2
    assert written['points'][-1]['count'] == 314925
    assert written['points'][-1]['month'][4] == '-'
    assert written.get('updated') != '2026-04-01'


def test_update_user_count_creates_history_when_missing(client, mocker):
    """Creates a new history entry when none exists."""
    mocker.patch('src.routes.db.count_users', return_value=100)
    mocker.patch('src.routes.db.get_setting', return_value=None)
    set_mock = mocker.patch('src.routes.db.set_setting')

    mock_claim = {'email': 'test-sa@example.iam.gserviceaccount.com'}
    with patch('src.routes._SCHEDULER_SA', 'test-sa@example.iam.gserviceaccount.com'), \
         patch('src.routes._SCHEDULER_AUDIENCE', 'https://example.com/admin/update-user-count'), \
         patch('google.oauth2.id_token.verify_oauth2_token', return_value=mock_claim):
        response = client.get(
            '/admin/update-user-count',
            headers={'Authorization': 'Bearer faketoken'}
        )

    assert response.status_code == 200
    set_mock.assert_called_once()
    _key, written_value = set_mock.call_args[0]
    written = json.loads(written_value)
    assert len(written['points']) == 1
    assert written['points'][0]['count'] == 100
```

- [ ] **Step 3: Add pytest-mock to requirements.txt and install**

Open `flaskHost/requirements.txt` and add this line after the `pytest==7.4.0` line:
```
pytest-mock==3.14.0
```

Then install:
```bash
cd flaskHost
pip install pytest-mock==3.14.0
```

- [ ] **Step 4: Run tests and confirm they fail**

```bash
cd flaskHost
python -m pytest tests/test_plotusers.py -v
```

Expected: all 6 tests FAIL with errors like `404 Not Found` for the `/plotusers` route or `ImportError`.

- [ ] **Step 5: Commit failing tests**

```bash
git add tests/__init__.py tests/conftest.py tests/test_plotusers.py
git commit -m "test: add failing tests for plotusers and update-user-count routes"
```

---

## Task 6: flaskHost — Implement plotusers routes and template

**Files:**
- Modify: `flaskHost/src/routes.py`
- Create: `flaskHost/src/templates/plotusers.html`

- [ ] **Step 1: Add missing imports to routes.py**

Open `flaskHost/src/routes.py`. Update the `from datetime import datetime` line to:

```python
from datetime import datetime, timezone
```

Add these two imports after the existing `from google.auth.transport import requests` line:

```python
from google.oauth2 import id_token
from google.auth.transport.requests import Request as GoogleAuthRequest
```

- [ ] **Step 2: Add scheduler constants after imports**

In `flaskHost/src/routes.py`, add these lines right after the `unreserved = ...` line and before the `app = db.wrap_app(app)` line:

```python
_SCHEDULER_AUDIENCE = os.environ.get('SCHEDULER_AUDIENCE', '')
_SCHEDULER_SA = os.environ.get('SCHEDULER_SA', '')
```

- [ ] **Step 3: Add /plotusers route to routes.py**

In `flaskHost/src/routes.py`, add this route after the `root()` function (after the `/index` route block):

```python
@app.route('/plotusers')
def plotusers():
    raw = db.get_setting('user_count_history')
    if not raw:
        return flask.render_template('plotusers.html', points=[], updated=None, no_data=True)
    try:
        history = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return flask.render_template('plotusers.html', points=[], updated=None, no_data=True)
    return flask.render_template('plotusers.html',
                                 points=history.get('points', []),
                                 updated=history.get('updated'),
                                 no_data=False)
```

- [ ] **Step 4: Add /admin/update-user-count route to routes.py**

Immediately after the `plotusers()` function, add:

```python
@app.route('/admin/update-user-count')
def update_user_count():
    auth_header = flask.request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer ') or not _SCHEDULER_SA or not _SCHEDULER_AUDIENCE:
        return flask.Response('Forbidden', status=403)
    try:
        claim = id_token.verify_oauth2_token(
            auth_header[7:], GoogleAuthRequest(), audience=_SCHEDULER_AUDIENCE
        )
        if claim.get('email') != _SCHEDULER_SA:
            return flask.Response('Forbidden', status=403)
    except Exception:
        return flask.Response('Forbidden', status=403)

    count = db.count_users()

    raw = db.get_setting('user_count_history')
    if not raw:
        history = {'points': []}
    else:
        try:
            history = json.loads(raw)
            if 'points' not in history:
                history['points'] = []
        except (json.JSONDecodeError, ValueError):
            history = {'points': []}

    now = datetime.now(timezone.utc)
    history['updated'] = now.strftime('%Y-%m-%d')
    history['points'].append({'month': now.strftime('%Y-%m'), 'count': count})

    db.set_setting('user_count_history', json.dumps(history))
    return flask.Response('OK', status=200)
```

- [ ] **Step 5: Create plotusers.html template**

Create `flaskHost/src/templates/plotusers.html` with the following content (identical to Classic — it uses standard Jinja2 compatible with flaskHost):

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Web VPython Users</title>
  <style>
    body { font-family: sans-serif; margin: 20px; }
    #chart { width: 100%; height: 600px; }
    .no-data { color: #888; font-style: italic; margin-top: 40px; }
  </style>
</head>
<body>
  <script src="/package/plotlyVP7.min.js"></script>

  {% if no_data %}
  <p class="no-data">No data yet — run <code>buildUserHistory.py</code> first.</p>
  {% else %}
  <div id="chart"></div>
  <script>
    const points = {{ points | tojson }};
    const updated = {{ updated | tojson }};

    function toDecimalYear(monthStr) {
      const [year, month] = monthStr.split('-').map(Number);
      return year + (month - 1) / 12;
    }

    if (points.length === 0) {
      document.getElementById('chart').innerHTML = '<p class="no-data">No data points available.</p>';
    } else {
      const xs = points.map(p => toDecimalYear(p.month));
      const ys = points.map(p => p.count);

      const lastPoint = points[points.length - 1];
      const formattedDate = updated ? updated.replace(/-/g, '/') : '';
      const formattedCount = lastPoint.count.toLocaleString();
      const title = `As of ${formattedDate} there were ${formattedCount} Web VPython accounts.`;

      try {
        Plotly.newPlot('chart', [{
          x: xs,
          y: ys,
          mode: 'lines+markers',
          type: 'scatter',
          marker: { color: 'red', size: 4 },
          line: { color: 'red', width: 1 }
        }], {
          title: title,
          xaxis: { title: 'Year' },
          yaxis: { title: 'Web VPython accounts' },
          margin: { t: 60 }
        });
      } catch (e) {
        document.getElementById('chart').innerHTML = '<p class="no-data">Chart failed to render: ' + e.message + '</p>';
      }
    }
  </script>
  {% endif %}
</body>
</html>
```

- [ ] **Step 6: Run tests and confirm they pass**

```bash
cd flaskHost
python -m pytest tests/test_plotusers.py -v
```

Expected: all 6 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/routes.py src/templates/plotusers.html
git commit -m "feat: add /plotusers and /admin/update-user-count routes with MongoDB-backed storage"
```

---

## Task 7: flaskHost — Spot-check ide.js for backend API changes

**Files:**
- Possibly modify: `flaskHost/src/ide.js`

- [ ] **Step 1: Run the diff and look for backend-communication changes only**

```bash
diff glowscript/ide/ide.js flaskHost/src/ide.js | grep "^[<>]" | grep -i "api\|fetch\|xhr\|postMessage\|url\|route\|endpoint" | head -30
```

- [ ] **Step 2: Review the filtered diff output**

You are looking for changes in Classic that affect how the IDE talks to the server — things like:
- Changed API endpoint paths (e.g., `/api/user/...`)
- Changed `postMessage` format sent to runners
- New API call signatures
- Changed request/response field names

Ignore any changes that are purely Monaco vs ACE editor code.

- [ ] **Step 3: Port any backend-communication changes found**

If the diff reveals no backend-communication changes, skip this step and note it in the commit.

If changes are found, apply only those to `flaskHost/src/ide.js`, being careful not to disturb the Monaco editor code.

- [ ] **Step 4: Commit**

```bash
cd flaskHost
# If no changes were needed:
git commit --allow-empty -m "chore: ide.js spot-check complete — no backend API changes found"
# If changes were applied:
git add src/ide.js
git commit -m "sync: port backend API changes from Classic ide.js"
```

---

## Verification Checklist

After all tasks complete, verify across all three repos:

**rsWVPRunner:**
- [ ] `diff glowscript/lib/glow/extrude.js rsWVPRunner/lib/glow/extrude.js` → no output
- [ ] `diff glowscript/lib/glow/primitives.js rsWVPRunner/lib/glow/primitives.js` → no output

**wmWVPRunner:**
- [ ] `static/vpython.zip` is not tracked by git (`git ls-files static/vpython.zip` → empty)
- [ ] `npm run zip && npm run build` completes without error
- [ ] `build/vpython.zip` exists and is nonzero

**flaskHost:**
- [ ] `python -m pytest tests/ -v` → all tests pass
- [ ] `docker build .` succeeds (Python 3.12 base)
- [ ] `/plotusers` loads in the running app
- [ ] `/admin/update-user-count` returns 403 without auth header
