# Home Assistant Add-on: Salt

This repository is being reset around a Home Assistant-first Salt runtime.

The add-on runs a persistent Salt master, a minimal ingress UI for key/minion
management, and Docker proxy minions for visible Home Assistant containers. The
repository also ships a normal Home Assistant custom integration under
`custom_components/salt` so accepted Salt minions can show up as native devices
with grain entities.

The old Materium/POP direction is preserved at tag
`pre-ha-first-rethink-2026-07-09`.

See [the Home Assistant-first plan](./docs/home-assistant-first-salt-plan.md)
for the implementation contract.

## Runtime

- `salt-master`
- `salt-ha-api`
- `salt-docker-proxy-supervisor`

Salt master config, PKI, caches, and proxy state persist under `/config/salt`.
The API caches grain responses under `/data/salt-ha-api`.

## Development

Install this repository as a Home Assistant add-on repository, install the Salt
add-on, and start it. The add-on image installs Salt from Python packages pinned
to the 3008 line.

For workstation-only add-on testing, use the shared compose file in
`/home/akmod/code`:

```bash
docker compose up --build --remove-orphans
```
