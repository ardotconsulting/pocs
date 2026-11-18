"""Adds, updates or removes one POC's monitor in Uptime Kuma, matched by name.

Called by terraform_data.kuma_monitor in pocs.tf. Uptime Kuma has no REST API
for monitors, so this speaks its Socket.IO API (what its web UI uses), signed
in as the admin. Never prints the password.

On add it also puts the monitor in the "Proofs of concept" group of the public
status page KUMA_STATUS_PAGE, keeping everything else on the page as it was.
Deleting a monitor takes it off the page; an emptied group is removed.

    kuma-monitor.py add|remove
Env: KUMA_URL, KUMA_USERNAME, KUMA_PASSWORD, KUMA_STATUS_PAGE, MONITOR_NAME,
     and for add MONITOR_URL
"""

import json
import os
import sys
import threading
import urllib.request

import socketio

GROUP = "Proofs of concept"

action = sys.argv[1] if len(sys.argv) > 1 else ""
if action not in ("add", "remove"):
    sys.exit("usage: kuma-monitor.py add|remove")

name = os.environ["MONITOR_NAME"]
url = os.environ.get("MONITOR_URL", "")
monitors: dict = {}
got_list = threading.Event()

sio = socketio.Client(reconnection=False)


@sio.on("monitorList")
def on_monitor_list(data):
    monitors.clear()
    monitors.update(data)
    got_list.set()


def call(event, data=None):
    res = sio.call(event, data, timeout=30)
    if not res or not res.get("ok"):
        sys.exit(f"Uptime Kuma {event} failed: {(res or {}).get('msg', 'no response')}")
    return res


def update_status_page(monitor_id=None):
    """Adds monitor_id to GROUP (if given) and drops GROUP if it's empty."""
    slug = os.environ["KUMA_STATUS_PAGE"]
    config = call("getStatusPage", slug)["config"]
    with urllib.request.urlopen(f"{os.environ['KUMA_URL']}/api/status-page/{slug}", timeout=30) as r:
        groups = json.load(r)["publicGroupList"]
    group = next((g for g in groups if g["name"] == GROUP), None)
    if monitor_id is not None:
        if group is None:
            group = {"name": GROUP, "monitorList": []}
            groups.append(group)
        if any(m["id"] == monitor_id for m in group["monitorList"]):
            return
        group["monitorList"].append({"id": monitor_id})
    elif group is None or group["monitorList"]:
        return
    else:
        groups.remove(group)
    # Keep each monitor's per-page settings (send/custom URL) as they were.
    for g in groups:
        g["monitorList"] = [{k: m[k] for k in ("id", "sendUrl", "url") if k in m} for m in g["monitorList"]]
    config["logo"] = config.get("icon")
    sio.call("saveStatusPage", (slug, config, config.get("icon") or "", groups), timeout=30)


sio.connect(os.environ["KUMA_URL"], transports=["websocket"], wait_timeout=30)
try:
    call("login", {"username": os.environ["KUMA_USERNAME"], "password": os.environ["KUMA_PASSWORD"], "token": ""})
    if not got_list.wait(30):
        sys.exit("Uptime Kuma didn't send its monitor list")
    existing = next((m for m in monitors.values() if m.get("name") == name), None)

    if action == "add":
        if existing and existing.get("url") == url:
            monitor_id = existing["id"]
            print(f"Uptime Kuma monitor already up to date: {name}")
        elif existing:
            existing["url"] = url
            call("editMonitor", existing)
            monitor_id = existing["id"]
            print(f"Updated Uptime Kuma monitor: {name}")
        else:
            monitor_id = call("add", {
                "type": "http", "name": name, "url": url, "method": "GET",
                "interval": 60, "retryInterval": 60, "resendInterval": 0, "maxretries": 2,
                "timeout": 48, "maxredirects": 10, "accepted_statuscodes": ["200-299"],
                "ignoreTls": False, "upsideDown": False, "expiryNotification": False,
                "notificationIDList": {}, "conditions": [], "kafkaProducerSaslOptions": {"mechanism": "None"},
                "description": "Proof of concept (managed by ardotconsulting/pocs)",
            })["monitorID"]
            print(f"Added Uptime Kuma monitor: {name}")
        update_status_page(monitor_id)
    else:
        if existing:
            call("deleteMonitor", existing["id"])
            print(f"Removed Uptime Kuma monitor: {name}")
        else:
            print(f"No Uptime Kuma monitor named {name}")
        update_status_page()
finally:
    sio.disconnect()
