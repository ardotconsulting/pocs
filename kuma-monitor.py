"""Adds, updates or removes one POC's monitor in Uptime Kuma, matched by name.

Called by terraform_data.kuma_monitor in pocs.tf. Uptime Kuma has no REST API
for monitors, so this speaks its Socket.IO API (what its web UI uses), signed
in as the admin. Never prints the password.

    kuma-monitor.py add|remove
Env: KUMA_URL, KUMA_USERNAME, KUMA_PASSWORD, MONITOR_NAME, and for add MONITOR_URL
"""

import os
import sys
import threading

import socketio

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


sio.connect(os.environ["KUMA_URL"], transports=["websocket"], wait_timeout=30)
try:
    call("login", {"username": os.environ["KUMA_USERNAME"], "password": os.environ["KUMA_PASSWORD"], "token": ""})
    if not got_list.wait(30):
        sys.exit("Uptime Kuma didn't send its monitor list")
    existing = next((m for m in monitors.values() if m.get("name") == name), None)

    if action == "add":
        if existing and existing.get("url") == url:
            print(f"Uptime Kuma monitor already up to date: {name}")
        elif existing:
            existing["url"] = url
            call("editMonitor", existing)
            print(f"Updated Uptime Kuma monitor: {name}")
        else:
            call("add", {
                "type": "http", "name": name, "url": url, "method": "GET",
                "interval": 60, "retryInterval": 60, "resendInterval": 0, "maxretries": 2,
                "timeout": 48, "maxredirects": 10, "accepted_statuscodes": ["200-299"],
                "ignoreTls": False, "upsideDown": False, "expiryNotification": False,
                "notificationIDList": {}, "conditions": [], "kafkaProducerSaslOptions": {"mechanism": "None"},
                "description": "Proof of concept (managed by ardotconsulting/pocs)",
            })
            print(f"Added Uptime Kuma monitor: {name}")
    else:
        if existing:
            call("deleteMonitor", existing["id"])
            print(f"Removed Uptime Kuma monitor: {name}")
        else:
            print(f"No Uptime Kuma monitor named {name}")
finally:
    sio.disconnect()
