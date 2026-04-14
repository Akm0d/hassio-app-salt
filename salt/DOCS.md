# Home Assistant Add-on: Salt

This add-on runs a Salt master together with SaltGUI. SaltGUI is published
through Home Assistant ingress, authenticated Home Assistant admin users are
automatically signed in, and the Salt state tree stays editable from the Home
Assistant host.

## What It Provides

- A Salt master listening on TCP `4505` and `4506`
- SaltGUI through an admin-only Home Assistant sidebar panel
- Automatic SaltGUI sign-in for authenticated Home Assistant admin users
- Internal `salt-api` service on TCP `3333`
- Editable Salt state and pillar trees at container `/srv/salt` and `/srv/pillar`
- Persistent Salt PKI, cache, job data, and tokens in `/data`

## Installation

1. Install the add-on.
2. Set a `gui_password`, or leave it blank once and read the generated password
   from the add-on log.
3. Start the add-on. The Salt master starts automatically as part of add-on
   startup.
4. Open the Salt sidebar panel in Home Assistant as an admin user.
5. The add-on signs you in to SaltGUI automatically.
   Manual logins use Salt's `pam` external auth with username `saltadmin`.
6. Point Salt minions at a hostname or IP address they can actually resolve and
   reach on ports `4505` and `4506`.

## Configuration

Sample configuration:

```yaml
log_level: info
gui_password: ""
auto_accept: false
```

### Option: `log_level`

Controls Salt master and API log verbosity.

### Option: `gui_password`

Password for the SaltGUI service account. If left empty, the add-on generates
one on first boot, stores it in `/data/generated_gui_password`, and prints it
to the log.

Manual SaltGUI logins use the fixed username `saltadmin`.

### Option: `auto_accept`

If enabled, the Salt master automatically accepts new minion keys. Leave this
disabled unless you intentionally want an open enrollment model.

## Fixed Master Defaults

This add-on intentionally keeps the core Salt master layout opinionated so the
Home Assistant integration stays predictable:

- `publish_port: 4505`
- `ret_port: 4506`
- `file_roots: /srv/salt`
- `pillar_roots: /srv/pillar`
- `pki_dir: /data/pki/master`
- `cachedir: /data/cache/master`
- `token_dir: /data/tokens`
- `sqlite_queue_dir: /data/queues`
- `state_events: True`
- internal `salt-api` / SaltGUI service on `127.0.0.1:3333`

Only `log_level`, `gui_password`, and `auto_accept` are exposed in the add-on
UI. Everything else uses these static defaults so minion connectivity, ingress,
and host-editable state paths stay consistent.

## File Layout

The add-on creates and uses these paths:

- `/srv/salt`
- `/srv/pillar`
- `/data/pki/master`
- `/data/cache/master`
- `/data/tokens`

If they do not exist yet, the add-on creates them automatically. It also writes
stub top files so the directories are ready to edit from the host without
shipping example states:

- `/srv/salt/top.sls`
- `/srv/pillar/top.sls`

Inside the container, Salt uses the standard `/srv/salt` and `/srv/pillar`
paths. Those are backed by Home Assistant's writable `share` mapping, so on the
host you edit:

- `/share/salt`
- `/share/pillar`

The cryptographic material and other Salt runtime data stay private and
persistent in `/data`.

## Access Paths

- Sidebar panel: Home Assistant ingress through `lighttpd`
- SaltGUI is intended to be opened from the Home Assistant sidebar
- Salt master ports for minions: `<home-assistant-host>:4505` and `:4506`

The SaltGUI HTTP service still runs internally on port `3333`, but it is not
advertised as the normal user entrypoint. The intended UI path is the admin-only
Home Assistant panel.

The Salt master ports are published on the Home Assistant host, so minions on
your LAN can connect without needing access to the add-on's internal Docker
network.

## Connecting Minions

Point a Salt minion at the Home Assistant host running this add-on:

```yaml
master: your-home-assistant-host
```

Then restart the minion and accept the key from SaltGUI or the Salt CLI.

## Security Notes

- The Home Assistant panel is marked admin-only.
- Home Assistant ingress identifies the authenticated user and the add-on
  creates a SaltGUI session for that request.
- The built-in SaltGUI service account `saltadmin` gets broad
  SaltGUI-compatible permissions:
  `.*`, `@runner`, `@wheel`, and `@jobs`.
- If you open SaltGUI without ingress auto-login, sign in manually as
  `saltadmin` with the configured or generated GUI password.
- The Salt master publishes on the host's standard `4505` and `4506` ports so
  LAN minions can connect without needing Docker-internal addressing.
- Set a strong password before exposing Salt master ports beyond your trusted
  network.
- `auto_accept: false` is the safer default.

## Changelog & Releases

This repository uses GitHub releases for version history.
