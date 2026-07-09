#!/usr/bin/env python3
"""Supervise one Salt Docker proxy minion process per HA Docker container."""

from __future__ import annotations

import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import time

import docker
import yaml


LOG_DIR = pathlib.Path("/srv/materium-dev/logs")
PROXY_STATE_ROOT = pathlib.Path("/config/materium/salt/proxies")
RECONCILE_INTERVAL = 10
MAX_NEW_PROXIES_PER_RECONCILE = 4


class ProxySupervisor:
    """Maintain Docker-backed salt-proxy processes for discovered containers."""

    def __init__(self) -> None:
        self.app_dir = pathlib.Path(os.environ["MATERIUM_APP_DIR"])
        self.master_port = int(os.environ.get("MATERIUM_MASTER_RET_PORT", "4506"))
        self.processes: dict[str, subprocess.Popen] = {}
        self.running = True
        self.client = docker.from_env(timeout=15)
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        PROXY_STATE_ROOT.mkdir(parents=True, exist_ok=True)

    def log(self, message: str) -> None:
        """Write one timestamped supervisor log line."""
        print(f"[materium-proxy-supervisor] {message}", flush=True)

    def proxy_path_name(self, container_name: str) -> str:
        """Return a filesystem-safe name for a proxy configuration directory."""
        return re.sub(r"[^A-Za-z0-9_.-]+", "_", container_name).strip("._") or "container"

    def config_dir(self, container_name: str) -> pathlib.Path:
        """Return the per-proxy Salt config directory."""
        return PROXY_STATE_ROOT / self.proxy_path_name(container_name) / "etc" / "salt"

    def write_proxy_config(self, container_name: str) -> pathlib.Path:
        """Persist Salt proxy config for one Docker container."""
        root = PROXY_STATE_ROOT / self.proxy_path_name(container_name)
        config_dir = root / "etc" / "salt"
        config_dir.mkdir(parents=True, exist_ok=True)
        for path in (root / "cache", root / "pki", root / "sock"):
            path.mkdir(parents=True, exist_ok=True)

        payload = {
            "id": container_name,
            "master": "127.0.0.1",
            "master_port": self.master_port,
            "cachedir": str(root / "cache"),
            "pki_dir": str(root / "pki"),
            "sock_dir": str(root / "sock"),
            "file_client": "local",
            "mine_enabled": False,
            "proxy_keep_alive": False,
            "log_level": "info",
            "log_file": "/dev/stderr",
            "proxy_merge_grains_in_module": True,
            "proxy": {
                "proxytype": "docker",
                "name": container_name,
            },
        }
        proxy_config = config_dir / "proxy"
        proxy_config.write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")
        return proxy_config

    def process_is_running(self, proc: subprocess.Popen | None) -> bool:
        """Return true when a proxy subprocess is still alive."""
        return proc is not None and proc.poll() is None

    def stop_existing_managed_proxy_processes(self) -> None:
        """Terminate older proxy processes that use this supervisor's config root."""
        managed_root = str(PROXY_STATE_ROOT)
        current_pid = os.getpid()
        for proc_dir in pathlib.Path("/proc").iterdir():
            if not proc_dir.name.isdigit():
                continue
            pid = int(proc_dir.name)
            if pid == current_pid:
                continue
            cmdline_path = proc_dir / "cmdline"
            try:
                cmdline = cmdline_path.read_bytes().replace(b"\x00", b" ").decode()
            except OSError:
                continue
            if "salt-proxy" not in cmdline or managed_root not in cmdline:
                continue
            self.log(f"stopping stale managed proxy pid={pid}")
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                continue
        time.sleep(2)
        for proc_dir in pathlib.Path("/proc").iterdir():
            if not proc_dir.name.isdigit():
                continue
            pid = int(proc_dir.name)
            if pid == current_pid:
                continue
            cmdline_path = proc_dir / "cmdline"
            try:
                cmdline = cmdline_path.read_bytes().replace(b"\x00", b" ").decode()
            except OSError:
                continue
            if "salt-proxy" not in cmdline or managed_root not in cmdline:
                continue
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                continue

    def proxy_command(self, container_name: str) -> list[str]:
        """Build the salt-proxy command for one proxy id."""
        return [
            "uv",
            "run",
            "--no-sync",
            "--extra",
            "test",
            "salt-proxy",
            "-c",
            str(self.config_dir(container_name)),
            "--proxyid",
            container_name,
            "--log-file=/dev/stderr",
        ]

    def start_proxy(self, container_name: str) -> None:
        """Start or restart one proxy process for a container."""
        current = self.processes.get(container_name)
        if self.process_is_running(current):
            return
        self.write_proxy_config(container_name)
        proxy_log = LOG_DIR / "proxies" / f"{self.proxy_path_name(container_name)}.log"
        proxy_log.parent.mkdir(parents=True, exist_ok=True)
        output = proxy_log.open("ab")
        proc = subprocess.Popen(
            self.proxy_command(container_name),
            cwd=str(self.app_dir),
            env=os.environ.copy(),
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        self.processes[container_name] = proc
        self.log(f"started proxy {container_name} pid={proc.pid}")

    def stop_proxy(self, container_name: str) -> None:
        """Stop one managed proxy process without deleting Salt keys."""
        proc = self.processes.pop(container_name, None)
        if not proc or proc.poll() is not None:
            return
        self.log(f"stopping proxy {container_name} pid={proc.pid}")
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=10)

    def stop_all_proxies(self) -> None:
        """Stop every proxy process currently owned by this supervisor."""
        for name in sorted(list(self.processes)):
            self.stop_proxy(name)

    def request_stop(self, signum: int, _frame: object) -> None:
        """Ask the reconciliation loop to stop after receiving a process signal."""
        self.log(f"received signal {signum}; stopping proxy supervisor")
        self.running = False

    def container_names(self) -> set[str]:
        """Return all visible Docker container names."""
        return {container.name for container in self.client.containers.list(all=True) if container.name}

    def validate_docker_access(self) -> None:
        """Check that Docker is reachable and report likely permission limits."""
        version = self.client.version()
        self.log(f"connected to Docker {version.get('Version', 'unknown')}")
        containers = self.client.containers.list(all=True)
        if not containers:
            self.log("Docker API is reachable but no containers are visible")
            return
        sample = containers[0]
        try:
            self.client.api.exec_create(sample.id, ["true"])
        except Exception as exc:  # noqa: BLE001 - startup diagnostic must log raw Docker permission failures.
            self.log(
                "Docker exec permission check failed; Docker proxy minions will connect, "
                f"but docker.call/state execution may fail: {exc}"
            )
        else:
            self.log("Docker exec permission check passed")

    def reconcile(self) -> None:
        """Start missing proxies and stop proxies for removed containers."""
        names = self.container_names()
        for stale in sorted(set(self.processes) - names):
            self.stop_proxy(stale)
        started = 0
        for name in sorted(names):
            current = self.processes.get(name)
            if not self.process_is_running(current) and started >= MAX_NEW_PROXIES_PER_RECONCILE:
                continue
            self.start_proxy(name)
            if not self.process_is_running(current):
                started += 1

    def run(self) -> int:
        """Run the Docker event loop with periodic reconciliation."""
        signal.signal(signal.SIGTERM, self.request_stop)
        signal.signal(signal.SIGINT, self.request_stop)
        self.stop_existing_managed_proxy_processes()
        try:
            self.validate_docker_access()
        except Exception as exc:  # noqa: BLE001 - Docker connection diagnostics should keep the supervisor alive.
            self.log(f"Docker API unavailable: {exc}")
        since = int(time.time())
        while self.running:
            try:
                self.reconcile()
                until = int(time.time() + RECONCILE_INTERVAL)
                for event in self.client.events(
                    decode=True,
                    filters={"type": "container"},
                    since=since,
                    until=until,
                ):
                    since = max(since, int(event.get("time", since)))
                    action = str(event.get("Action", ""))
                    if action in {"create", "start", "die", "destroy", "rename"}:
                        self.reconcile()
                since = int(time.time())
            except KeyboardInterrupt:
                break
            except Exception as exc:  # noqa: BLE001 - supervisor should report Docker/Salt failures and retry.
                self.log(f"supervisor loop error: {exc}")
                time.sleep(RECONCILE_INTERVAL)
        self.stop_all_proxies()
        return 0


def main() -> int:
    """Start the proxy supervisor from environment-provided runtime config."""
    try:
        return ProxySupervisor().run()
    except Exception as exc:  # noqa: BLE001 - top-level startup should print a direct operational error.
        print(
            json.dumps(
                {
                    "error": str(exc),
                    "hint": "Docker proxy supervisor could not start; check add-on Docker API permissions.",
                },
            ),
            file=sys.stderr,
            flush=True,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
