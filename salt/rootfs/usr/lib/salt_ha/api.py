"""Small key and minion management API for the Salt add-on."""

from __future__ import annotations

import os
from typing import Any

from aiohttp import web

from salt_ha import runtime


def json_response(data: Any, status: int = 200) -> web.Response:
    """Return JSON with a stable top-level object."""
    return web.json_response(data, status=status)


async def health(_request: web.Request) -> web.Response:
    """Return API and Salt CLI health."""
    return json_response(await runtime.health())


async def keys(_request: web.Request) -> web.Response:
    """Return Salt keys grouped by status."""
    return json_response({"data": await runtime.list_keys()})


async def key_action(request: web.Request) -> web.Response:
    """Accept, reject, or delete submitted minion keys."""
    action = request.match_info["action"]
    if action not in {"accept", "reject", "delete"}:
        return json_response({"error": "unsupported action"}, status=404)
    payload = await request.json()
    ids = [str(item) for item in payload.get("ids", []) if str(item)]
    return json_response({"results": await runtime.manage_keys(action, ids)})


async def minions(_request: web.Request) -> web.Response:
    """Return merged minion rows."""
    return json_response({"data": await runtime.minion_rows()})


async def minion_grains(request: web.Request) -> web.Response:
    """Return minion rows with cached grains, optionally refreshing first."""
    if request.query.get("refresh") in {"1", "true", "yes"}:
        await runtime.refresh_grains()
    return json_response({"data": await runtime.minion_rows()})


async def refresh_grains(_request: web.Request) -> web.Response:
    """Refresh cached minion grains."""
    return json_response(await runtime.refresh_grains())


async def prefixed_api_or_index(request: web.Request) -> web.Response:
    """Handle Home Assistant app/ingress paths that preserve a URL prefix."""
    tail = request.match_info["tail"].lstrip("/")
    parts = tail.split("/")
    try:
        api_index = len(parts) - 1 - list(reversed(parts)).index("api")
    except ValueError:
        return await index(request)

    api_parts = parts[api_index + 1 :]
    if request.method == "GET" and api_parts == ["health"]:
        return await health(request)
    if request.method == "GET" and api_parts == ["keys"]:
        return await keys(request)
    if request.method == "POST" and len(api_parts) == 2 and api_parts[0] == "keys":
        action = api_parts[1]
        if action not in {"accept", "reject", "delete"}:
            return json_response({"error": "unsupported action"}, status=404)
        payload = await request.json()
        ids = [str(item) for item in payload.get("ids", []) if str(item)]
        return json_response({"results": await runtime.manage_keys(action, ids)})
    if request.method == "GET" and api_parts == ["minions"]:
        return await minions(request)
    if request.method == "GET" and api_parts == ["minions", "grains"]:
        return await minion_grains(request)
    if request.method == "POST" and api_parts == ["minions", "refresh-grains"]:
        return await refresh_grains(request)
    return json_response({"error": "not found"}, status=404)


async def index(_request: web.Request) -> web.Response:
    """Serve the minimal ingress UI."""
    return web.Response(
        content_type="text/html",
        text="""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Salt</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    main { max-width: 1120px; margin: 0 auto; padding: 24px; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    h1 { font-size: 28px; margin: 0; }
    h2 { font-size: 18px; margin: 28px 0 12px; }
    button { cursor: pointer; border: 1px solid ButtonBorder; background: ButtonFace; color: ButtonText; padding: 6px 10px; border-radius: 6px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border-bottom: 1px solid color-mix(in srgb, CanvasText 16%, transparent); padding: 8px; text-align: left; vertical-align: top; }
    th { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .actions { display: flex; gap: 6px; flex-wrap: wrap; }
    .muted { opacity: .7; }
    .pill { display: inline-block; border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 999px; padding: 2px 8px; font-size: 12px; }
    .error { color: #b3261e; }
  </style>
</head>
<body>
<main>
  <header>
    <h1>Salt</h1>
    <div class="actions">
      <button type="button" onclick="refreshGrains()">Refresh Grains</button>
      <button id="accept-all" type="button" onclick="acceptAll()" disabled>Accept All</button>
      <button type="button" onclick="load()">Reload</button>
    </div>
  </header>
  <p id="health" class="muted">Loading...</p>
  <h2>Keys</h2>
  <table>
    <thead><tr><th>Status</th><th>Minion</th><th>Actions</th></tr></thead>
    <tbody id="keys"></tbody>
  </table>
  <h2>Minions</h2>
  <table>
    <thead><tr><th>Minion</th><th>Status</th><th>Last Refresh</th><th>Grains</th></tr></thead>
    <tbody id="minions"></tbody>
  </table>
</main>
<script>
let pendingKeyIds = [];

function setBusy(message) {
  document.getElementById('health').textContent = message;
  document.querySelectorAll('button').forEach(button => { button.disabled = true; });
}

async function api(path, options = {}) {
  const route = String(path).replace(/^\\/+/, '');
  const page = window.location.pathname.replace(/\\/+$/, '');
  const basePath = page.endsWith('/salt') ? page.slice(0, -5) : page;
  const target = `${window.location.origin}${basePath}/${route}${window.location.search}`;
  const response = await fetch(target, {
    headers: {'content-type': 'application/json'},
    ...options,
  });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function keyActions(status, id) {
  const actions = [];
  if (status === 'pending') actions.push(['accept', 'Accept'], ['reject', 'Reject']);
  if (status !== 'pending') actions.push(['delete', 'Delete']);
  return `<div class="actions">${actions.map(([action, label]) => `<button type="button" data-action="${action}" data-id="${esc(id)}">${label}</button>`).join('')}</div>`;
}
async function keyAction(action, id) {
  try {
    setBusy(`${action === 'accept' ? 'Accepting' : action === 'reject' ? 'Rejecting' : 'Deleting'} ${id}...`);
    await api(`/api/keys/${action}`, {method: 'POST', body: JSON.stringify({ids: [id]})});
    await load();
  } catch (err) {
    document.getElementById('health').innerHTML = `<span class="error">${esc(err.message)}</span>`;
    await load();
  }
}
async function acceptAll() {
  if (!pendingKeyIds.length) return;
  try {
    setBusy(`Accepting ${pendingKeyIds.length} pending keys...`);
    await api('/api/keys/accept', {method: 'POST', body: JSON.stringify({ids: pendingKeyIds})});
    document.getElementById('health').textContent = `Accepted ${pendingKeyIds.length} keys. Waiting for minions to reconnect...`;
    await load();
  } catch (err) {
    document.getElementById('health').innerHTML = `<span class="error">${esc(err.message)}</span>`;
    await load();
  }
}
async function refreshGrains() {
  try {
    setBusy('Refreshing Docker grains...');
    const result = await api('/api/minions/refresh-grains', {method: 'POST'});
    const failures = Object.keys(result.errors || {}).length;
    document.getElementById('health').textContent = `Refreshed ${result.updated?.length || 0} minion grains${failures ? `, ${failures} failed` : ''} - ${result.last_refresh || ''}`;
    await load();
  } catch (err) {
    document.getElementById('health').innerHTML = `<span class="error">${esc(err.message)}</span>`;
    await load();
  }
}
async function load() {
  try {
    const [health, keys, minions] = await Promise.all([
      api('/api/health'),
      api('/api/keys'),
      api('/api/minions/grains'),
    ]);
    document.getElementById('health').textContent = `${health.salt || 'Salt'} - ${health.time}`;
    const keyRows = [];
    pendingKeyIds = keys.data.pending || [];
    for (const [status, ids] of Object.entries(keys.data)) {
      for (const id of ids) keyRows.push(`<tr><td><span class="pill">${esc(status)}</span></td><td><code>${esc(id)}</code></td><td>${keyActions(status, id)}</td></tr>`);
    }
    document.getElementById('keys').innerHTML = keyRows.join('') || '<tr><td colspan="3" class="muted">No keys.</td></tr>';
    document.querySelectorAll('button[data-action]').forEach(button => {
      button.addEventListener('click', () => keyAction(button.dataset.action, button.dataset.id));
    });
    document.querySelectorAll('button').forEach(button => { button.disabled = false; });
    document.getElementById('accept-all').disabled = pendingKeyIds.length === 0;
    document.getElementById('minions').innerHTML = minions.data.map(row => {
      const grains = row.grains || {};
      const preview = ['os', 'osrelease', 'kernel', 'host', 'fqdn'].filter(k => grains[k] !== undefined).map(k => `${k}: ${grains[k]}`).join('<br>');
      return `<tr><td><code>${esc(row.id)}</code></td><td><span class="pill">${esc(row.key_status)}</span></td><td>${esc(row.last_refresh || '')}</td><td>${preview || '<span class="muted">No cached grains</span>'}</td></tr>`;
    }).join('') || '<tr><td colspan="4" class="muted">No minions.</td></tr>';
  } catch (err) {
    document.getElementById('health').innerHTML = `<span class="error">${esc(err.message)}</span>`;
  }
}
load();
</script>
</body>
</html>
""",
    )


def create_app() -> web.Application:
    """Create the aiohttp application."""
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_get("/api/health", health)
    app.router.add_get("/api/keys", keys)
    app.router.add_post("/api/keys/{action}", key_action)
    app.router.add_get("/api/minions", minions)
    app.router.add_get("/api/minions/grains", minion_grains)
    app.router.add_post("/api/minions/refresh-grains", refresh_grains)
    app.router.add_route("*", "/{tail:.*}", prefixed_api_or_index)
    return app


def main() -> None:
    """Run the local API server."""
    host = os.environ.get("SALT_HA_API_HOST", "0.0.0.0")
    port = int(os.environ.get("SALT_HA_API_PORT", "8099"))
    web.run_app(create_app(), host=host, port=port)


if __name__ == "__main__":
    main()
