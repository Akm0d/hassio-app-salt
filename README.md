# Home Assistant Add-on: Salt

This repository is the Home Assistant add-on wrapper for Materium, the Salt UI
and service layer.

The target add-on runtime is Materium-first:

- no SaltGUI
- no `salt-api`
- direct Salt master/minion management through Materium
- Home Assistant ingress for `materium-web`
- supervised `salt-master`, local `salt-minion`, `materium-web`, and
  `materium-worker` services, plus a dev-only restart marker watcher
- persistent Salt and Materium storage under `/data`

Materium itself lives in the
[`Akm0d/materium`](https://github.com/Akm0d/materium) application repository.
This add-on repository owns packaging, ingress, service supervision, and
Home Assistant docs/config.

See [the add-on documentation](./salt/DOCS.md) for the runtime layout and
configuration model.

## Home Assistant development loop

Install this repository as a Home Assistant add-on repository, then install the
Salt add-on. For rapid Materium development on a real Home Assistant host, sync
the local Materium checkout into Home Assistant storage before enabling
development mode:

```bash
tar -C /home/akmod/code/materium -czf - . \
  | ssh root@salt "mkdir -p /share/materium-dev/materium && tar -xzf - -C /share/materium-dev/materium"
```

Then turn on the add-on development options:

```yaml
dev_mode: true
dev_source: /srv/materium-dev/materium
```

The add-on sees that path as `/srv/materium-dev/materium`. From the shared
`/home/akmod/code` workspace, use the VS Code task
`HA: sync + restart Materium` to sync source and touch a restart marker in
`/share/materium-dev`. The add-on watches that marker and restarts only
`materium-web` and `materium-worker`.

## Local dev container

For workstation-only testing, use the VS Code launch entry
`hassio-app-salt: docker compose up`, or run:

```bash
docker compose up --build --remove-orphans
```

The compose file lives in the parent `/home/akmod/code` workspace. It builds
the add-on image, bind-mounts the local Materium checkout over `/opt/materium`,
and runs the container in the foreground. Stop it with `Ctrl+C`.
