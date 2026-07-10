# Home Assistant Add-on: Salt

This add-on runs a persistent Salt master for Home Assistant and exposes a
small key/minion management UI through ingress.

## Runtime

The add-on starts three services:

- `salt-master`
- `salt-ha-api`
- `salt-docker-proxy-supervisor`

`salt-master` is the real Salt master. LAN minions connect to the add-on host on
ports `4505/tcp` and `4506/tcp`.

`salt-ha-api` serves both the ingress UI and a small JSON API for the Home
Assistant integration:

- `GET /api/health`
- `GET /api/keys`
- `POST /api/keys/accept`
- `POST /api/keys/reject`
- `POST /api/keys/delete`
- `GET /api/minions`
- `GET /api/minions/grains`
- `POST /api/minions/refresh-grains`

`salt-docker-proxy-supervisor` discovers visible Home Assistant Docker
containers and starts one Salt proxy minion per container. Proxy keys are not
auto-accepted unless `master.auto_accept` is enabled.

## Persistent Storage

Salt state is stored in Home Assistant config storage:

```text
/config/salt/master/etc/salt/master
/config/salt/master/pki
/config/salt/master/cache
/config/salt/master/sock
/config/salt/master/srv/salt
/config/salt/master/srv/pillar
/config/salt/proxies/<proxy-id>
```

The API stores cached grain responses in:

```text
/data/salt-ha-api/grains.json
```

The add-on rewrites generated config on startup, but it does not delete Salt
PKI, accepted keys, rejected keys, denied keys, or proxy minion state.

## Options

```yaml
ui:
  host: 0.0.0.0
  port: 8099
docker_proxy:
  enabled: true
  include_stopped: true
master:
  log_level: info
  auto_accept: false
  worker_threads: 50
  publish_port: 4505
  ret_port: 4506
```

`ui.port` should normally match the committed ingress port. The Salt ports
should normally stay at the standard `4505` and `4506` values.

## Home Assistant Integration

The matching custom integration lives in `custom_components/salt`. It polls the
add-on API, creates one Home Assistant device for each accepted minion, and
exposes selected grains as entities.

Reload the integration after accepting new keys to force device/entity
rediscovery immediately. Normal polling will keep grain values refreshed after
that.
