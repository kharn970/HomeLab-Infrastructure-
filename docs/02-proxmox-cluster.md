# 2. Proxmox VE cluster

[← Back to overview](../README.md)

## Cluster

| Item | Value |
|---|---|
| Platform | Proxmox VE 9.2 |
| Cluster | 3 nodes, quorate, no HA groups (workloads are pinned per node) |
| Storage | Per-node LVM-thin for guest disks, directory storage for ISOs and templates, shared Proxmox Backup Server datastore |
| Management | Web UI on any node from the LAN or the VPN only; read-only auditor account for documentation |

## Nodes

| Node | CPU | RAM | System disk | Extra storage | Bridge |
|---|---|---|---|---|---|
| pve | Core i3-9100T, 4C/4T | 16 GB | 256 GB NVMe | n/a | `vmbr0` |
| pve3 | Core i7-6700T, 4C/8T | 16 GB | 512 GB NVMe | n/a | `vmbr0` |
| pve4 | Core i5-11500, 6C/12T | 32 GB | 500 GB NVMe | 1 TB HDD (LVM-thin `HDD-Backup`) | `vmbr0`, VLAN-aware; spare PCIe NIC passed through to VM 210 |

## Workloads

### LXC containers (all unprivileged Debian)

| ID | Service | Node | vCPU / RAM | Notes |
|---|---|---|---|---|
| 100 | CouchDB | pve3 | 2 / 4 GB | Back end for self-hosted Obsidian note sync; also reachable over Tailscale |
| 101 | File server (TurnKey) | pve | 2 / 512 MB | 100 GB data volume; Samba |
| 102 | AdGuard Home | pve | 1 / 1 GB | Network-wide DNS filtering |
| 103 | Pulse | pve | 1 / 1 GB | Proxmox monitoring; reads the API through a scoped token |
| 104 | n8n | pve4 | 2 / 2 GB | Workflow automation |
| 105 | Rendering service | pve3 | 2 / 2 GB | Uses AdGuard directly for DNS |
| 107 | Navidrome | pve3 | 2 / 1 GB | Music streaming; library is a host bind mount |
| 109 | OctoFiesta | pve3 | 2 / 2 GB | Docker host; shares the music bind mount |
| 200 | Proxmox Backup Server | pve4 | 2 / 4 GB | 700 GB datastore on the HDD |

### Virtual machines (KVM)

| ID | VM | Node | vCPU / RAM | Disk | Network |
|---|---|---|---|---|---|
| 106 | Ubuntu Server 26.04 test | pve3 | 2 / 4 GB | 32 GB | VLAN 1; `Hardened` snapshot |
| 108 | Security tooling (Kali Linux) | pve3 | 2 / 4 GB | 80 GB | Tagged for VLAN 3 but currently receives a Default-network address ([roadmap](05-security-and-operations.md#audit-and-remediation-roadmap)); `FreshInstall` snapshot |
| 210 | pfSense DMZ firewall | pve4 | 2 / 4 GB | 20 GB | WAN on VLAN 99; DMZ on a passed-through PCIe NIC ([section 7](07-dmz-honeypot.md)) |
| 220 | Windows 11 workstation | pve4 | 2 / 12 GB (balloon) | 120 GB on HDD | VLAN 2; UEFI + vTPM 2.0 |

## Access model

| Account | Realm | Rights | Used for |
|---|---|---|---|
| Administrator | Linux PAM | Full | Administration |
| Auditor account | Proxmox VE | `PVEAuditor` on `/` | Read-only documentation and audits |
| Monitoring service account | Proxmox VE | Monitoring role plus datastore read | Pulse dashboard, via an API token |

Separate service and audit identities mean the monitoring tool and documentation work never use root.
