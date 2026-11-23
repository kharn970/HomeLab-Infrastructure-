# Honeypot alerting

Two read-only Python scripts for the T-Pot sensor that post to a Discord webhook. Background and design are in [section 7](../../docs/07-dmz-honeypot.md#alerting).

| File | Purpose |
|---|---|
| `honeypot-digest.py` + `.service` / `.timer` | Daily summary at 08:00: attacks by honeypot, top sources, countries, credentials, commands, captured malware hashes, top IDS signatures |
| `honeypot-alert.py` + `.service` / `.timer` | Checks every 5 minutes: real SSH activity on the sensor, IDS alerts on connections the sensor itself started, silent pipeline, disk usage |

Both use only the Python standard library and query T-Pot's Elasticsearch on `127.0.0.1:64298`.

## Install

```bash
sudo install -m 755 honeypot-digest.py honeypot-alert.py /usr/local/bin/
sudo install -m 644 *.service *.timer /etc/systemd/system/
sudo install -d -m 700 /etc/honeypot-digest
sudo sh -c 'umask 077; cat > /etc/honeypot-digest/webhook'   # paste the webhook URL, Enter, Ctrl+D
sudo systemctl daemon-reload
python3 /usr/local/bin/honeypot-digest.py --dry-run            # preview without sending
sudo systemctl enable --now honeypot-digest.timer honeypot-alert.timer
```

Set `ADMIN_IPS` in `honeypot-alert.service` to the admin workstation's address before enabling it.

## Hardening

- Each run uses a throwaway unprivileged account (`DynamicUser=yes`); the webhook URL is passed in with `LoadCredential` from a root-only file, so the scripts never need root.
- Text chosen by attackers (usernames, commands, URLs) is treated as hostile: mentions are disabled, backticks and line breaks are stripped, and URLs are defanged (`hxxp`).
- Use a dedicated Discord channel and webhook so a leaked URL can only post to that channel.
