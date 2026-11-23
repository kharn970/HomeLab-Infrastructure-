# Changelog

Notable infrastructure changes to the lab, newest first.

## 2026-11-22

- DMZ honeypot went live: T-Pot on a dedicated laptop behind the pfSense firewall VM, with Suricata IDS on the firewall and default-deny, rate-limited egress. See section 7 of the documentation.
- VLAN 99 moved from per-network isolation to explicit UniFi DMZ zone policies.
- pfSense updated to 2.9.2; DHCP moved from ISC to Kea.

## 2026-11-19

- pfSense VM: a spare PCIe NIC on a Proxmox node passed through as the DMZ interface, replacing a missing bridge that had been failing the VM's backups.

## 2026-11-17

- Backup verification now reads guest exclusions directly from the Proxmox backup job, so the daily report and the backup policy stay in sync.
- Disposable lab guests (Ubuntu test VM, pfSense lab firewall, Windows 11 workstation) excluded from nightly backups by policy.

## 2026-11-16

- Added automated monitoring with n8n: daily backup verification, stopped-guest alerts, disk-space thresholds and a weekly inventory diff.

## 2026-11-15

- Added VM 108 (security tooling, Kali Linux) on pve3, VLAN 3.
- Published the initial infrastructure documentation and inventory scripts.
