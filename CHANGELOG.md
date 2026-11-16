# Changelog

Notable infrastructure changes to the lab, newest first.

## 2026-11-16

- Added automated monitoring with n8n: daily backup verification, stopped-guest alerts, disk-space thresholds and a weekly inventory diff.
- Monitoring found VM 210 (pfSense lab) failing its nightly backup because of a missing bridge, and a node running its backup window in the wrong time zone; both added to the remediation roadmap.

## 2026-11-15

- Added VM 108 (security tooling, Kali Linux) on pve3, VLAN 3.
- Published the initial infrastructure documentation and inventory scripts.
