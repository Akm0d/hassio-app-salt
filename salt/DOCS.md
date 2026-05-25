# Home Assistant Add-on: Salt

This add-on is the Home Assistant wrapper for Materium. Materium is the Salt
application; this repository supplies the add-on packaging, ingress, service
supervision, and persistent storage layout.

## Runtime Direction

The Materium runtime replaces the old SaltGUI/salt-api design:

- Materium manages Salt directly with Salt's Python APIs.
- No `salt-api` process is required.
- No SaltGUI ingress proxy is required.
- Home Assistant ingress serves `materium-web`.
- Supervised services are:
  - `salt-master`
  - `salt-minion`
  - `materium-web`
  - `materium-worker`
  - `materium-dev-reloader`

The add-on runtime no longer starts SaltGUI, `salt-api`, or an ingress proxy.

## Configuration Model

The committed Materium config in the application repository is a template. The
Home Assistant add-on should generate a runtime Materium config with the same
shape.

The important option is `salt.base_dir`. Materium rewrites managed Salt paths
under that directory so the add-on can keep runtime data in persistent Home
Assistant storage.

Recommended add-on storage shape:

```yaml
salt:
  base_dir: /data/materium
  master:
    log_level: info
  minion:
    log_level: info
    master: localhost
```

The `salt.master` and `salt.minion` sections describe Materium-managed embedded
processes. They are not intended to expose arbitrary Salt master/minion config
through the Home Assistant options UI.

For live development on a real Home Assistant host, the add-on auto-detects
synced Materium source at `/srv/materium-dev/materium`. When that path contains
`pyproject.toml`, `materium-web` and `materium-worker` run from the synced
source and uv keeps the development virtual environment under
`/data/materium/dev-venv`. Otherwise the add-on runs the packaged path
`/opt/materium`.

## Persistent Storage Layout

With `salt.base_dir: /data/materium`, Materium-generated paths live under:

- `/data/materium/master`
- `/data/materium/minion`
- `/data/materium/cache.sqlite3`
- `/data/materium/targets.yaml`

The Salt file and pillar roots are generated from the master layout:

- `/data/materium/master/srv/salt`
- `/data/materium/master/srv/pillar`

The add-on may map or symlink these to host-editable locations if needed, but
Materium should remain the owner of the generated Salt configuration.

## Service Controls

Materium exposes service status and restart hooks:

```text
GET  /api/runtime/services
POST /api/runtime/services/salt-master/restart
POST /api/runtime/services/salt-minion/restart
```

In the add-on, these endpoints should call the supervisor/s6 restart mechanism
for the embedded `salt-master` and local `salt-minion` services.

Remote minion restart is intentionally outside this v1 runtime control surface.
It can later be implemented as a normal Salt job.

## Salt Access

Minions connect to the embedded Salt master on standard Salt transport ports:

- `4505/tcp`: Salt publish port
- `4506/tcp`: Salt return port

Materium reads keys, minions, grains, jobs, events, state functions, formulas,
targets, SLS, and pillar through direct Salt APIs and cached read models.
Views should render cached data first and refresh in the background.

## Local Wrapper Testing

Use the Materium repository for Python development and the end-to-end Salt
integration tests:

```bash
cd materium
uv sync --extra test
uv run pytest
```

For live Home Assistant development, install this repository as an add-on
repository, then sync source from the shared workspace. The image does not clone
the private Materium repository during build.

```bash
/home/akmod/code/sync-materium-to-ha.sh
```

From `/home/akmod/code`, the VS Code task `HA: sync + restart Materium` performs
the same sync and touches `/share/materium-dev/restart`. The add-on's
`materium-dev-reloader` service watches the matching container path and restarts
only `materium-web` and `materium-worker`.

Use this add-on repository for Home Assistant packaging and container smoke
tests. From the shared `/home/akmod/code` workspace, press the VS Code launch
entry `hassio-app-salt: docker compose up`, or run:

```bash
docker compose up --build --remove-orphans
```

The local dev harness uses:

- container name: `materium-addon-dev`
- Materium web: `http://127.0.0.1:8099/`
- Salt publish/return ports: `4505` and `4506`
- storage: `/home/akmod/code/.dev/hassio-app-salt`

It builds the image and runs `salt-master`, `salt-minion`, `materium-web`,
`materium-worker`, and `materium-dev-reloader` in the foreground so Docker's
normal output is the debug surface.
