# Home Assistant Add-on: Salt

This repository contains a Home Assistant add-on that runs a Salt master and
SaltGUI.

The add-on:

- serves SaltGUI through an admin-only Home Assistant ingress panel
- signs in authenticated Home Assistant admin users automatically
- uses the fixed manual SaltGUI username `saltadmin`
- runs `salt-api` internally on port `3333`
- exposes the Salt master transport on ports `4505` and `4506`
- persists Salt PKI, cache, job data, and tokens in `/data`
- uses standard Salt paths `/srv/salt` and `/srv/pillar`
- backs those paths with Home Assistant's host-editable `share` storage as
  `/share/salt` and `/share/pillar`

Those ports are fixed so the add-on matches standard Salt defaults.

See [the add-on documentation](./salt/DOCS.md) for setup and configuration.

<img width="3840" height="1025" alt="image" src="https://github.com/user-attachments/assets/ecb49042-26ae-40f5-902f-ceaf4a68a160" />
