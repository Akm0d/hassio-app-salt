# Home Assistant Add-on: Salt

This repository is the Home Assistant add-on wrapper for Materium, the Salt UI
and service layer.

The target add-on runtime is Materium-first:

- no SaltGUI
- no `salt-api`
- direct Salt master and proxy-minion management through Materium
- Home Assistant ingress for `materium-web`
- supervised `salt-master`, Docker proxy supervisor, `materium-web`, and
  `materium-worker` services, plus a dev-only restart marker watcher
- persistent Salt and Materium storage under `/data`
- dynamic Docker proxy minions for every visible Home Assistant container

Materium itself lives in the
[`Akm0d/materium`](https://github.com/Akm0d/materium) application repository.
This add-on repository owns packaging, ingress, service supervision, and
Home Assistant docs/config.

See [the add-on documentation](./salt/DOCS.md) for the runtime layout and
configuration model.

## Home Assistant development loop

Install this repository as a Home Assistant add-on repository, then install the
Salt add-on. The image does not clone the private Materium repository during
build; for rapid development, sync the local Materium checkout into Home
Assistant storage before starting the add-on:

```bash
/home/akmod/code/sync-materium-to-ha.sh
```

The script syncs to `akmod@hearth:/share/materium-dev/materium` and touches
`/share/materium-dev/restart`. The add-on sees that source as
`/srv/materium-dev/materium` and runs from it automatically when
`pyproject.toml` is present. The add-on watches the restart marker and restarts
only `materium-web` and `materium-worker`.

## Local dev container

For workstation-only testing, use the VS Code launch entry
`hassio-app-salt: docker compose up`, or run:

```bash
docker compose up --build --remove-orphans
```

The compose file lives in the parent `/home/akmod/code` workspace. It builds
the add-on image, bind-mounts the local Materium checkout over `/opt/materium`,
and runs the container in the foreground. Stop it with `Ctrl+C`.
