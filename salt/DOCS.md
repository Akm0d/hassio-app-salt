# Home Assistant Add-on: Salt

This add-on runs a Salt master together with SaltGUI. SaltGUI is served by
Salt's own `rest_cherrypy` API on port `3333`, while a small `lighttpd` proxy
handles Home Assistant ingress on port `8099`.

## What It Provides

- A Salt master listening on TCP `4505` and `4506`
- SaltGUI and `salt-api` on TCP `3333`
- Home Assistant sidebar access through ingress
- Editable Salt state and pillar trees in `/srv`

## Installation

1. Install the add-on.
2. Set a `gui_password`, or leave it blank once and read the generated password
   from the add-on log.
3. Start the add-on.
4. Open the sidebar panel or `OPEN WEB UI`.
5. Log in with the configured `gui_username` using auth method `pam`.

## Configuration

Sample configuration:

```yaml
log_level: info
gui_username: saltadmin
gui_password: ""
auto_accept: false
```

### Option: `log_level`

Controls Salt master and API log verbosity.

### Option: `gui_username`

Linux user account created inside the add-on for SaltGUI login. Salt's
`external_auth` is configured for this user with full SaltGUI-compatible
permissions.

### Option: `gui_password`

Password for the SaltGUI login user. If left empty, the add-on generates one on
first boot, stores it in `/data/generated_gui_password`, and prints it to the
log.

### Option: `auto_accept`

If enabled, the Salt master automatically accepts new minion keys. Leave this
disabled unless you intentionally want an open enrollment model.

## File Layout

The add-on creates and uses these paths:

- `/srv/salt`
- `/srv/pillar`
- `/data/pki/master`
- `/data/cache/master`

If they do not exist yet, the add-on creates them automatically. It also writes
starter files:

- `/srv/salt/top.sls`
- `/srv/salt/example/init.sls`
- `/srv/pillar/top.sls`

Inside the container, Salt uses the standard `/srv/salt` and `/srv/pillar`
paths. Those are backed by Home Assistant's writable `share` mapping, so on the
host you edit:

- `/share/salt`
- `/share/pillar`

## Access Paths

- Sidebar panel: Home Assistant ingress through `lighttpd`
- Direct UI: `http://<home-assistant-host>:3333/`
- Salt master ports for minions: `<home-assistant-host>:4505` and `:4506`

These ports are fixed by the add-on and are not configurable from the options
screen.

## Connecting Minions

Point a Salt minion at the Home Assistant host running this add-on:

```yaml
master: your-home-assistant-host
```

Then restart the minion and accept the key from SaltGUI or the Salt CLI.

## Security Notes

- SaltGUI login uses Salt `external_auth` via PAM.
- The configured GUI user gets broad SaltGUI-compatible permissions:
  `.*`, `@runner`, `@wheel`, and `@jobs`.
- Set a strong password before exposing port `3333` or Salt master ports beyond
  your trusted network.
- `auto_accept: false` is the safer default.

## Changelog & Releases

This repository uses GitHub releases for version history.
