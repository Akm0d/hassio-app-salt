# Home Assistant-first Salt Plan

## Goal

Run a persistent Salt master from the Home Assistant add-on and expose Salt
minions as native Home Assistant devices under a normal, repository-shipped Salt
integration.

The add-on should own the Salt runtime. Home Assistant should own visibility,
automation, and day-to-day operations. The web UI should be limited to key and
minion management.

## Non-goals

- No HACS-only install path.
- No SaltGUI revival.
- No Materium/POP runtime requirement for v1.
- No SSH minion management in v1.
- No state, pillar, formula, orchestration, or job-runner UI in v1.
- No local Salt minion started inside the add-on unless it becomes explicitly
  useful later.

## Runtime Shape

The add-on runs these long-lived services:

- `salt-master`
- `salt-ha-api`
- `salt-docker-proxy-supervisor`

`salt-master` is the source of truth for keys, connected minions, and grains.
`salt-ha-api` is a small HTTP service used by both the add-on ingress UI and the
Home Assistant integration. `salt-docker-proxy-supervisor` keeps the existing
Docker proxy-minion idea: one Salt proxy process per visible Home Assistant
container.

Salt should be installed from Python packages, pinned to the 3008 line:

```text
salt>=3008,<3009
```

That keeps the image on the current 3008 LTS line without relying on Alpine's
Salt package cadence.

## Persistence

All Salt identity, master config, PKI, caches, and generated proxy-minion config
must survive add-on restarts and image upgrades.

Preferred layout:

```text
/config/salt/master/etc/salt/master
/config/salt/master/pki
/config/salt/master/cache
/config/salt/master/sock
/config/salt/proxies/<proxy-id>/etc/salt/proxy
/config/salt/proxies/<proxy-id>/pki
/config/salt/proxies/<proxy-id>/cache
/data/salt-ha-api/cache.sqlite
```

The add-on writes Salt master config at startup from Home Assistant options, but
it must not delete existing PKI, accepted keys, rejected keys, or proxy config.

## Add-on Options

Keep options minimal:

```yaml
master:
  log_level: info
  auto_accept: false
  worker_threads: 50
  publish_port: 4505
  ret_port: 4506
docker_proxy:
  enabled: true
  include_stopped: true
ui:
  host: 0.0.0.0
  port: 8099
```

The published Salt ports remain `4505/tcp` and `4506/tcp` so LAN minions can
connect directly to the add-on-hosted master.

## API Contract

The local API is intentionally small and stable:

```text
GET  /api/health
GET  /api/keys
POST /api/keys/accept       {"ids": ["minion-a"]}
POST /api/keys/reject       {"ids": ["minion-a"]}
POST /api/keys/delete       {"ids": ["minion-a"]}
GET  /api/minions
GET  /api/minions/grains
POST /api/minions/refresh-grains
```

`/api/minions` should merge key status, presence if available, and cached grain
metadata. `/api/minions/grains` should return a Home Assistant-friendly payload:

```json
{
  "data": [
    {
      "id": "minion-a",
      "key_status": "accepted",
      "online": true,
      "grains": {
        "os": "Ubuntu",
        "osrelease": "24.04",
        "kernel": "Linux"
      },
      "last_seen": "2026-07-09T12:00:00Z",
      "last_refresh": "2026-07-09T12:00:00Z"
    }
  ]
}
```

## Add-on Web UI

The ingress UI is only for key and minion management:

- pending, accepted, rejected, and denied key lists
- accept, reject, delete actions
- minion search/filter
- compact grain preview for accepted minions
- refresh grains action
- basic health/status display for `salt-master` and Docker proxy supervisor

No state authoring, command runner, formula catalog, or orchestration pages are
needed for v1.

## Home Assistant Integration

The repository should include a normal custom integration at:

```text
custom_components/salt/
```

It should be installable from the repository without HACS-specific behavior.

Integration responsibilities:

- config flow for add-on/local API URL and optional token if auth is added
- `DataUpdateCoordinator` polling `/api/minions/grains`
- one Home Assistant device per accepted minion
- diagnostic entities for key status, online status, and last refresh
- grain entities under each minion device
- a reload should rediscover minions and grain entities from the latest API
  payload

Initial entity mapping:

- `binary_sensor.<minion>_online`
- `sensor.<minion>_key_status`
- `sensor.<minion>_last_refresh`
- selected common grain sensors: `os`, `osrelease`, `kernel`, `kernelrelease`,
  `host`, `fqdn`, `cpu_model`, `num_cpus`, `mem_total`
- any remaining scalar grains as disabled-by-default diagnostic sensors

Nested grains should be flattened with dot-separated keys for entity unique IDs.
Lists and dictionaries should be exposed as entity attributes only when a stable
scalar sensor would be awkward.

## Implementation Sequence

1. Preserve old direction with a commit and tag.
2. Replace Materium naming and docs with Salt/Home Assistant naming.
3. Change the add-on image from Alpine Salt packages to a uv-managed Python
   environment pinned to `salt>=3008,<3009`.
4. Build `salt-ha-api` as a small aiohttp service inside the add-on.
5. Rework init scripts and s6 services around `salt-master`, `salt-ha-api`, and
   `salt-docker-proxy-supervisor`.
6. Port the existing Docker proxy supervisor to the new paths and naming.
7. Add the `custom_components/salt` integration scaffold.
8. Implement coordinator, devices, and grain entities.
9. Add focused tests for API payload normalization and HA entity construction.
10. Smoke test on `hearth.local`: add-on starts, pending keys appear, keys can
    be accepted, reload creates minion devices/entities.

## First Working Milestone

The first useful build should prove this loop:

1. Add-on starts `salt-master`.
2. API returns pending keys and accepted minions.
3. Ingress UI can accept a pending key.
4. A Docker proxy minion appears as pending, can be accepted, and reports grains.
5. The Home Assistant integration reloads and creates a device for that minion
   with grain entities.

