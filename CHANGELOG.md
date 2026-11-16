# Changelog

Infrastructure changes to the lab, newest first. Weekly entries are generated automatically: an n8n workflow pulls the inventory from the Proxmox API every Sunday, compares it with the previous week and commits any changes here.

<!-- n8n:entries -->

## 2026-11-16

- Added automated monitoring with n8n: daily backup verification, stopped-guest alerts, disk-space thresholds and this weekly changelog.
- Monitoring found VM 210 (pfSense lab) failing its nightly backup because of a missing bridge, and a node running its backup window in the wrong time zone; both added to the remediation roadmap.

## 2026-11-15

- Added VM 108 (security tooling, Kali Linux) on pve3, VLAN 3.
- Published the initial infrastructure documentation and inventory scripts.
