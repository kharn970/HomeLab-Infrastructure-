#!/usr/bin/env python3
"""
honeypot-digest.py - daily T-Pot summary posted to a Discord webhook.

Read-only: it only queries T-Pot's local Elasticsearch and never changes data.
Run by systemd (honeypot-digest.timer). Test with:  python3 honeypot-digest.py --dry-run
"""
import datetime
import json
import os
import re
import sys
import urllib.request

ES_URL = os.environ.get("ES_URL", "http://127.0.0.1:64298")   # T-Pot's Elasticsearch (localhost only)
INDEX = "logstash-*"
HOURS = int(os.environ.get("DIGEST_HOURS", "24"))
SENSOR_IP = os.environ.get("SENSOR_IP", "10.99.10.10")      # the honeypot's own address
NOISY_SIDS = [2100486]                                      # GPL ICMP "administratively prohibited"
NON_ATTACK_TYPES = ["Suricata", "P0f", "Fatt"]              # IDS and passive fingerprinting, not attacks
STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/honeypot-digest")
DRY_RUN = "--dry-run" in sys.argv


# ---------- Elasticsearch helpers ----------
def es(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(ES_URL + path, data=data, method="POST" if data else "GET",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

_caps = {}
def field(name):
    """Return (aggregatable_field_name, type) for name or name.keyword, or (None, None)."""
    if name not in _caps:
        caps = es(f"/{INDEX}/_field_caps?fields={name},{name}.keyword").get("fields", {})
        _caps[name] = (None, None)
        for cand in (name, name + ".keyword"):
            for ftype, info in caps.get(cand, {}).items():
                if info.get("aggregatable"):
                    _caps[name] = (cand, ftype)
                    break
            if _caps[name][0]:
                break
    return _caps[name]

def private_source_filters():
    """Queries matching private (RFC 1918 / loopback) source addresses."""
    f, ftype = field("src_ip")
    if not f:
        return []
    if ftype == "ip":                                       # CIDR matching on ip-typed fields
        return [{"term": {f: c}} for c in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8")]
    return [{"prefix": {f: "10."}}, {"prefix": {f: "192.168."}}, {"prefix": {f: "127."}},
            {"regexp": {f: "172\\.(1[6-9]|2[0-9]|3[01])\\..*"}}]

def term(name, value):
    f, _ = field(name)
    return {"term": {f or name: value}}

def query(must=(), must_not=(), external_only=True):
    flt = [{"range": {"@timestamp": {"gte": f"now-{HOURS}h"}}}] + list(must)
    nots = [term("type", "NGINX")] + list(must_not)        # NGINX = your own web-UI traffic
    if external_only:
        nots += private_source_filters()
    return {"bool": {"filter": flt, "must_not": nots}}

def count(q):
    return es(f"/{INDEX}/_count", {"query": q})["count"]

def top(name, q, n=5):
    f, _ = field(name)
    if not f:
        return []
    r = es(f"/{INDEX}/_search", {"size": 0, "query": q,
                                 "aggs": {"t": {"terms": {"field": f, "size": n}}}})
    return [(b["key"], b["doc_count"]) for b in r["aggregations"]["t"]["buckets"]]

def unique(name, q):
    f, _ = field(name)
    if not f:
        return 0
    r = es(f"/{INDEX}/_search", {"size": 0, "query": q, "aggs": {"u": {"cardinality": {"field": f}}}})
    return r["aggregations"]["u"]["value"]


# ---------- Formatting (attacker-controlled text is sanitised) ----------
def clean(value, limit=40):
    s = re.sub(r"[`\r\n\t]", " ", str(value))               # no code-block breakouts or line injection
    s = re.sub(r"(?i)\bhttp", "hxxp", s)                    # defang URLs so nobody clicks them
    return s[:limit] + ("…" if len(s) > limit else "")

def lines(items, fmt=lambda k: f"`{clean(k)}`"):
    return "\n".join(f"{fmt(k)} · {c:,}" for k, c in items) or "–"

def cap(text, limit=1024):
    return text if len(text) <= limit else text[: limit - 1] + "…"


# ---------- Main ----------
def main():
    # Honeypot attacks only: no IDS alerts, no passive fingerprinting, no private sources
    attacks = query(must_not=[{"terms": {field("type")[0] or "type": NON_ATTACK_TYPES}}])
    total = count(attacks)
    sources = unique("src_ip", attacks)
    by_pot = top("type", attacks, 8)
    countries = top("geoip.country_name", attacks, 5)
    attackers = top("src_ip", attacks, 5)

    cowrie = lambda ev: query(must=[term("eventid", ev)])
    users = top("username", cowrie("cowrie.login.failed"), 5)
    passwords = top("password", cowrie("cowrie.login.failed"), 5)
    logins_ok = count(cowrie("cowrie.login.success"))
    commands = top("input", cowrie("cowrie.command.input"), 5)
    hashes = top("shasum", cowrie("cowrie.session.file_download"), 5)

    suri_not = [{"terms": {field("alert.signature_id")[0] or "alert.signature_id": NOISY_SIDS}},
                {"prefix": {field("alert.signature")[0] or "alert.signature": "SURICATA STREAM"}}]
    signatures = top("alert.signature", query(must=[term("type", "Suricata")], must_not=suri_not), 5)

    # Red flag: IDS alerts on connections the sensor itself STARTED. Egress only allows 80/443, so a
    # sensor-initiated connection goes TO port 80/443; replies to attackers go to their random ports.
    # ET INFO / ET HUNTING / SURICATA protocol-anomaly rules are too noisy to act on.
    sig = field("alert.signature")[0] or "alert.signature"
    sensor_q = query(must=[term("type", "Suricata"), term("src_ip", SENSOR_IP),
                           {"terms": {field("dest_port")[0] or "dest_port": [80, 443]}}],
                     must_not=suri_not + [{"prefix": {sig: p}} for p in ("ET INFO", "ET HUNTING", "SURICATA ")],
                     external_only=False)
    sensor_alerts = top("alert.signature", sensor_q, 5)

    # Mark malware hashes never reported before
    seen_file = os.path.join(STATE_DIR, "seen_hashes.txt")
    seen = set(open(seen_file).read().split()) if os.path.exists(seen_file) else set()
    hash_lines = "\n".join(f"{'🆕 ' if h not in seen else ''}`{clean(h, 16)}` · {c}" for h, c in hashes) or "–"

    red = bool(sensor_alerts)
    embed = {
        "title": f"{'⚠️ ' if red else ''}Honeypot daily digest · last {HOURS} h",
        "description": f"**{total:,}** honeypot attacks from **{sources:,}** unique IPs · "
                       f"**{logins_ok:,}** accepted Cowrie logins",
        "color": 0xE53935 if red else 0x2E7D32,
        "fields": [
            {"name": "By honeypot", "value": cap(lines(by_pot, lambda k: clean(k))), "inline": True},
            {"name": "Top countries", "value": cap(lines(countries, lambda k: clean(k))), "inline": True},
            {"name": "Top source IPs", "value": cap(lines(attackers)), "inline": True},
            {"name": "Top usernames tried", "value": cap(lines(users)), "inline": True},
            {"name": "Top passwords tried", "value": cap(lines(passwords)), "inline": True},
            {"name": "Malware captured (SHA-256)", "value": cap(hash_lines), "inline": True},
            {"name": "Top commands", "value": cap(lines(commands, lambda k: f"`{clean(k, 60)}`"))},
            {"name": "Top IDS signatures", "value": cap(lines(signatures, lambda k: clean(k, 70)))},
            {"name": "⚠️ IDS alerts FROM the sensor" if red else "IDS alerts from the sensor",
             "value": cap(lines(sensor_alerts, lambda k: clean(k, 70))) if red else "None ✅"},
        ],
        "footer": {"text": "Test traffic from private addresses excluded · no digest = check the sensor"},
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    payload = {"username": "Honeypot digest", "embeds": [embed],
               "allowed_mentions": {"parse": []}}           # attacker strings can never ping anyone

    if DRY_RUN:
        print(json.dumps(payload, indent=2))
        return

    webhook_file = os.path.join(os.environ.get("CREDENTIALS_DIRECTORY", "/etc/honeypot-digest"), "webhook")
    url = open(webhook_file).read().strip()
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json",
                                          "User-Agent": "honeypot-digest/1.0"})
    urllib.request.urlopen(req, timeout=30).close()

    os.makedirs(STATE_DIR, exist_ok=True)
    with open(seen_file, "w") as fh:
        fh.write("\n".join(sorted(seen | {h for h, _ in hashes})))
    print(f"Digest sent: {total} events, {sources} sources, sensor alerts: {len(sensor_alerts)}")


if __name__ == "__main__":
    main()
