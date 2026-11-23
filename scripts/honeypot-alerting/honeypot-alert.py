#!/usr/bin/env python3
"""
honeypot-alert.py - near-real-time alerts from the T-Pot sensor to Discord.

Runs every 5 minutes (honeypot-alert.timer). Read-only. Each event is alerted once.
  RED    real SSH (port 64295) activity from anything other than the admin workstation
  RED    IDS alert on a connection the sensor itself started (to port 80/443) with no
         matching Cowrie download (a Cowrie download at the same time = expected payload fetch)
  AMBER  no honeypot attacks recorded for 60 minutes (pipeline or port forwards broken)
  AMBER  root filesystem above 85%
Test with:  python3 honeypot-alert.py --dry-run
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

ES_URL = os.environ.get("ES_URL", "http://127.0.0.1:64298")
INDEX = "logstash-*"
SENSOR_IP = os.environ.get("SENSOR_IP", "10.99.10.10")
ADMIN_IPS = set(os.environ.get("ADMIN_IPS", "").split())     # set in the service file
LOOKBACK_MIN = 10                                            # overlaps the 5-minute schedule
QUIET_MIN = 60
DISK_PCT = 85
REPEAT_AMBER_H = 6                                           # re-send an ongoing amber issue every 6 h
STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/honeypot-alert")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
DRY_RUN = "--dry-run" in sys.argv
NOISY_PREFIXES = ("ET INFO", "ET HUNTING", "SURICATA ")


def es(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(ES_URL + path, data=data, method="POST" if data else "GET",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

_caps = {}
def f(name):
    """Aggregatable/exact-match variant of a field (name or name.keyword)."""
    if name not in _caps:
        caps = es(f"/{INDEX}/_field_caps?fields={name},{name}.keyword").get("fields", {})
        _caps[name] = next((c for c in (name, name + ".keyword")
                            if any(v.get("aggregatable") for v in caps.get(c, {}).values())), name)
    return _caps[name]

def clean(value, limit=120):
    s = re.sub(r"[`@\r\n\t]", " ", str(value))               # no formatting breakouts or mentions
    s = re.sub(r"(?i)\bhttp", "hxxp", s)
    return s[:limit] + ("…" if len(s) > limit else "")


# ---------- Checks ----------
def check_real_ssh(since_epoch):
    """sshd log lines on the real SSH service from any address not in ADMIN_IPS."""
    out = subprocess.run(["journalctl", "-t", "sshd", "-t", "sshd-session", f"--since=@{int(since_epoch)}",
                          "-o", "json", "--no-pager"], capture_output=True, text=True, timeout=30).stdout
    alerts = []
    for line in out.splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        msg = entry.get("MESSAGE", "")
        if not isinstance(msg, str):
            continue
        m = re.search(r"from (\S+) port", msg)
        if not m or m.group(1) in ADMIN_IPS:
            continue
        key = "ssh:" + entry.get("__CURSOR", msg)
        level = "red"
        title = "Real SSH login on the sensor" if msg.startswith("Accepted") else "Real SSH port reached from an unexpected address"
        alerts.append((key, level, title, clean(msg, 300)))
    return alerts

def check_sensor_ids(since_iso):
    """Only real IDS alerts (event_type alert): Suricata also logs ordinary TLS/HTTP/flow records."""
    sig = f("alert.signature")
    q = {"bool": {"filter": [{"range": {"@timestamp": {"gte": since_iso}}},
                             {"term": {f("type"): "Suricata"}}, {"term": {f("event_type"): "alert"}},
                             {"exists": {"field": "alert.signature"}}, {"term": {f("src_ip"): SENSOR_IP}},
                             {"terms": {f("dest_port"): [80, 443]}}],
                  "must_not": [{"prefix": {sig: p}} for p in NOISY_PREFIXES]}}
    hits = es(f"/{INDEX}/_search", {"size": 20, "query": q, "sort": [{"@timestamp": "asc"}]})["hits"]["hits"]
    alerts = []
    for h in hits:
        src = h["_source"]
        a = src.get("alert", {})
        ts = src.get("@timestamp", "")
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        win = {"gte": (t - datetime.timedelta(minutes=3)).isoformat(), "lte": (t + datetime.timedelta(minutes=3)).isoformat()}
        fetch = es(f"/{INDEX}/_count", {"query": {"bool": {"filter": [
            {"range": {"@timestamp": win}}, {"term": {f("eventid"): "cowrie.session.file_download"}}]}}})["count"]
        detail = (f"**{clean(a.get('signature', '?'))}** (SID {a.get('signature_id', '?')}, severity {a.get('severity', '?')})\n"
                  f"Sensor → `{clean(src.get('dest_ip', '?'), 40)}:{src.get('dest_port', '?')}` at {ts}")
        if fetch:
            alerts.append(("ids:" + h["_id"], "amber", "Sensor outbound alert, likely a Cowrie payload fetch (expected)",
                           detail + f"\n{fetch} Cowrie download(s) within ±3 min."))
        else:
            alerts.append(("ids:" + h["_id"], "red", "IDS alert on a connection the SENSOR started",
                           detail + "\nNo Cowrie download at that time. Investigate; use the kill switch if unexplained."))
    return alerts

def check_quiet(state, now):
    q = {"bool": {"filter": [{"range": {"@timestamp": {"gte": f"now-{QUIET_MIN}m"}}}],
                  "must_not": [{"terms": {f("type"): ["Suricata", "P0f", "Fatt", "NGINX"]}}]}}
    n = es(f"/{INDEX}/_count", {"query": q})["count"]
    return repeatable(state, now, "quiet", n == 0, "No honeypot attacks for 60 minutes",
                      "An internet-facing honeypot is never this quiet. Check the port forwards, pfSense and T-Pot containers.")

def check_disk(state, now):
    u = shutil.disk_usage("/")
    pct = round(u.used * 100 / u.total)
    return repeatable(state, now, "disk", pct >= DISK_PCT, f"Sensor disk at {pct}%",
                      "T-Pot keeps 30 days of data; reduce retention or clean up before it fills.")

def repeatable(state, now, name, active, title, detail):
    """Amber conditions: alert when they start, then every REPEAT_AMBER_H while ongoing."""
    last = state["amber"].get(name)
    if not active:
        state["amber"].pop(name, None)
        return []
    if last and now - last < REPEAT_AMBER_H * 3600:
        return []
    state["amber"][name] = now
    return [(f"amber:{name}:{int(now)}", "amber", title, detail)]


# ---------- Main ----------
def main():
    now = time.time()
    state = {"seen": {}, "amber": {}}
    if os.path.exists(STATE_FILE):
        state.update(json.load(open(STATE_FILE)))
    since_epoch = now - LOOKBACK_MIN * 60
    since_iso = datetime.datetime.fromtimestamp(since_epoch, datetime.timezone.utc).isoformat()

    candidates = check_real_ssh(since_epoch) + check_sensor_ids(since_iso) + check_quiet(state, now) + check_disk(state, now)
    new = [c for c in candidates if c[0] not in state["seen"]][:10]          # at most 10 per run
    for key, *_ in new:
        state["seen"][key] = now
    state["seen"] = {k: v for k, v in state["seen"].items() if now - v < 86400}   # forget after a day

    if new:
        colors = {"red": 0xE53935, "amber": 0xFB8C00}
        icons = {"red": "🔴", "amber": "🟠"}
        embeds = [{"title": f"{icons[lvl]} {title}", "description": detail[:4000], "color": colors[lvl],
                   "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()}
                  for _, lvl, title, detail in new]
        payload = {"username": "Honeypot alert", "embeds": embeds, "allowed_mentions": {"parse": []}}
        if DRY_RUN:
            print(json.dumps(payload, indent=2))
        else:
            url = open(os.path.join(os.environ.get("CREDENTIALS_DIRECTORY", "/etc/honeypot-digest"), "webhook")).read().strip()
            req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST",
                                         headers={"Content-Type": "application/json", "User-Agent": "honeypot-alert/1.0"})
            urllib.request.urlopen(req, timeout=30).close()
    elif DRY_RUN:
        print("No new alerts.")

    if not DRY_RUN:
        os.makedirs(STATE_DIR, exist_ok=True)
        json.dump(state, open(STATE_FILE, "w"))
    print(f"{len(new)} alert(s) sent" if new and not DRY_RUN else "", end="")


if __name__ == "__main__":
    main()
