"""Adds, updates or removes one POC's monitor in Uptime Kuma, matched by name.

Called by terraform_data.kuma_monitor in pocs.tf. Uptime Kuma has no REST API
for monitors, so this speaks its Socket.IO API (what its web UI uses), signed
in as the admin. Never prints the password.

A POC that isn't serving yet (no 2xx) gets a paused monitor that stays off the
public status page KUMA_STATUS_PAGE; once it's live, the monitor is resumed and
put in the page's "Proofs of concept" group, keeping everything else on the page
as it was. `activate` does that for every paused POC monitor that has gone live
(run on a schedule by .github/workflows/activate.yml). Deleting a monitor takes
it off the page; an emptied group is removed.

    kuma-monitor.py add|remove|activate
Env: KUMA_URL, KUMA_USERNAME, KUMA_PASSWORD, KUMA_STATUS_PAGE, and for
     add/remove MONITOR_NAME, for add MONITOR_URL
"""

import fcntl
import json
import os
import sys
import threading
import urllib.request

import socketio

GROUP = "Proofs of concept"
MARKER = "Proof of concept (managed by ardotconsulting/pocs)"

action = sys.argv[1] if len(sys.argv) > 1 else ""
if action not in ("add", "remove", "activate"):
    sys.exit("usage: kuma-monitor.py add|remove|activate")

name = os.environ.get("MONITOR_NAME", "")
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


def is_live(target):
    """True if the app answers 2xx (after redirects). A POC with no app yet gets
    a 404 from the proxy, which doesn't count."""
    try:
        with urllib.request.urlopen(target, timeout=15) as r:
            return 200 <= r.status < 300
    except Exception:
        return False


def set_active(monitor, active):
    if bool(monitor.get("active")) != active:
        call("resumeMonitor" if active else "pauseMonitor", monitor["id"])


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
    # Keep each monitor's per-page settings (send/custom URL) as they were, and
    # drop duplicates (concurrent saves once listed a monitor twice).
    for g in groups:
        seen = set()
        g["monitorList"] = [
            {k: m[k] for k in ("id", "sendUrl", "url") if k in m}
            for m in g["monitorList"]
            if not (m["id"] in seen or seen.add(m["id"]))
        ]
    config["logo"] = config.get("icon")
    sio.call("saveStatusPage", (slug, config, config.get("icon") or "", groups), timeout=30)


# OpenTofu runs one of these per POC in parallel, and saving the status page is
# read-modify-write, so take turns (they all run on the same machine).
lock = open(os.path.join(os.environ.get("TMPDIR", "/tmp"), "kuma-monitor.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)

sio.connect(os.environ["KUMA_URL"], transports=["websocket"], wait_timeout=30)
try:
    call("login", {"username": os.environ["KUMA_USERNAME"], "password": os.environ["KUMA_PASSWORD"], "token": ""})
    if not got_list.wait(30):
        sys.exit("Uptime Kuma didn't send its monitor list")
    existing = next((m for m in monitors.values() if m.get("name") == name), None)

    if action == "add":
        live = is_live(url)
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
                "description": MARKER,
            })["monitorID"]
            print(f"Added Uptime Kuma monitor: {name}")
        if existing:
            set_active(existing, live)
        elif not live:
            call("pauseMonitor", monitor_id)
        if live:
            update_status_page(monitor_id)
        else:
            print(f"{name} isn't serving yet: monitor paused and kept off the status page")
    elif action == "activate":
        woken = 0
        for m in monitors.values():
            if m.get("description") == MARKER and not m.get("active") and is_live(m.get("url") or ""):
                set_active(m, True)
                update_status_page(m["id"])
                print(f"{m['name']} is live: monitor resumed and added to the status page")
                woken += 1
        print(f"Activated {woken} monitor(s).")
    else:
        if existing:
            call("deleteMonitor", existing["id"])
            print(f"Removed Uptime Kuma monitor: {name}")
        else:
            print(f"No Uptime Kuma monitor named {name}")
        update_status_page()
finally:
    sio.disconnect()
