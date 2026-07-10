"""Constants for the Salt integration."""

from __future__ import annotations

from datetime import timedelta

DOMAIN = "salt"
DEFAULT_NAME = "Salt"
DEFAULT_URL = "http://salt:8099"
UPDATE_INTERVAL = timedelta(minutes=1)

CONF_URL = "url"

PLATFORMS = ["binary_sensor", "sensor"]

COMMON_GRAINS = {
    "os",
    "osrelease",
    "kernel",
    "kernelrelease",
    "host",
    "fqdn",
    "cpu_model",
    "num_cpus",
    "mem_total",
}

