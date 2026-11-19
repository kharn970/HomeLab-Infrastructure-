# Changelog

Notable infrastructure changes to the lab, newest first.

Guest additions, removals, migrations and resizes are detected from the Proxmox API and committed here automatically each Sunday when there is something to report; design and process changes are added by hand.

## 2026-11-17

- Backup verification now reads guest exclusions directly from the Proxmox backup job, so the daily report and the backup policy stay in sync.
- Disposable lab guests (Ubuntu test VM, pfSense lab firewall, Windows 11 workstation) excluded from nightly backups by policy.

## 2026-11-16

- Added automated monitoring with n8n: daily backup verification, stopped-guest alerts, disk-space thresholds and a weekly inventory diff.

## 2026-11-15

- Added VM 108 (security tooling, Kali Linux) on pve3, VLAN 3.
- Published the initial infrastructure documentation and inventory scripts.
