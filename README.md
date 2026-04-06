# Home Assistant Add-on: Salt

This repository contains a Home Assistant add-on that runs a Salt master and
SaltGUI.

The add-on:

- serves SaltGUI and `salt-api` on port `3333`
- exposes the Salt master transport on ports `4505` and `4506`
- uses Home Assistant ingress for the sidebar panel
- stores master PKI and cache in `/data`
- stores editable states and pillars in `/share/salt`

Those ports are fixed so the add-on matches standard Salt defaults.

See [the add-on documentation](./salt/DOCS.md) for setup and configuration.
