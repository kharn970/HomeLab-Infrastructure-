# Home Lab Infrastructure

![Proxmox VE](https://img.shields.io/badge/Proxmox_VE-9.2-E57000?logo=proxmox&logoColor=white)
![Hyper-V](https://img.shields.io/badge/Hyper--V-Gen_2-0078D4?logo=windows&logoColor=white)
![Windows Server](https://img.shields.io/badge/Windows_Server-2025-0078D4?logo=windows&logoColor=white)
![Active Directory](https://img.shields.io/badge/Active_Directory-AGDLP_%7C_GPO-0078D4)
![Entra ID](https://img.shields.io/badge/Microsoft_Entra-Connect_%7C_Intune-0078D4?logo=microsoft&logoColor=white)
![UniFi](https://img.shields.io/badge/UniFi-5_VLANs-0559C9?logo=ubiquiti&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-automation-5391FE?logo=powershell&logoColor=white)

A self-built hybrid Windows and Linux environment that I design, run and document like a small-business network: a **3-node Proxmox VE cluster**, a **Hyper-V host** running an **Active Directory domain** with **hybrid identity to Microsoft Entra ID and Intune**, a **segmented UniFi network**, filtered DNS, VPN-only remote access and nightly backups.

The documentation is written as an operations handover, the way I'd leave it for another administrator: design, inventory, access model, backup strategy, runbooks and a prioritized remediation roadmap from my own audit.

---

## At a glance

| | |
|---|---|
| **Compute** | 4 physical hosts (3 Proxmox nodes + 1 Hyper-V host): 40 CPU threads, 112 GB RAM, about 3.3 TB of storage |
| **Workloads** | 9 LXC containers and 4 KVM VMs on Proxmox; 6 Hyper-V VMs |
| **Identity** | `corp.example.com` AD domain: 2 Windows Server 2025 DCs, department OUs, AGDLP, GPO, Entra Connect, Intune |
| **Network** | UniFi gateway and switch, 5 VLANs (2 isolated), DHCP reservations, AdGuard DNS filtering |
| **Remote access** | Tailscale mesh VPN with a subnet router; zero inbound ports |
| **Backup** | Proxmox Backup Server with nightly deduplicated jobs and server-side pruning |
| **Tooling** | Read-only PowerShell and Bash inventory scripts, Proxmox REST API, PowerShell Direct |

## Architecture

```mermaid
flowchart TB
  ISP["Fiber ISP"] --> GW["UniFi Cloud Gateway Ultra<br/>firewall · DHCP · inter-VLAN routing"]
  GW --> SW["UniFi Switch Lite 8 PoE"]
  GW --> WIFI["Wi-Fi mesh · VLAN 3"]

  subgraph V1["VLAN 1 · Infrastructure 192.168.1.0/24"]
    direction TB
    PVE["Proxmox VE cluster<br/>pve · pve3 · pve4"]
    PBS["Proxmox Backup Server"]
    DNS["AdGuard Home"]
    MON["Pulse monitoring · n8n automation"]
  end

  subgraph V2["VLAN 2 · Windows Server 192.168.2.0/24"]
    direction TB
    HV["Hyper-V host"]
    DC1["DC01<br/>main DC · Entra Connect"]
    DC2["DC02<br/>DC · DNS · FSMO"]
    W11["Windows 11 clients"]
  end

  subgraph ISO["VLAN 4 + 99 · isolated"]
    HP["Honeypot (in progress)"]
    PF["pfSense lab WAN"]
  end

  SW --> V1
  GW --> V2
  GW --> ISO
  DC1 <-->|replication| DC2
  DC1 -.->|sync| ENTRA["Microsoft Entra ID · Intune"]
  PVE -->|nightly| PBS
  GW -->|upstream DNS| DNS
  TS["Tailscale VPN"] -.->|subnet router| PVE
```

## Documentation

| # | Section | What's covered |
|---|---|---|
| 1 | [Network](docs/01-network.md) | Topology, VLAN design and isolation, IP plan, DNS path, remote access |
| 2 | [Proxmox VE cluster](docs/02-proxmox-cluster.md) | Nodes, storage, every container and VM, access model |
| 3 | [Hyper-V and Active Directory](docs/03-hyper-v-and-active-directory.md) | Hyper-V host and VMs, AD design, OUs, AGDLP, GPOs, hybrid identity |
| 4 | [Backup and recovery](docs/04-backup-and-recovery.md) | Backup layers, PBS design, retention, known gaps |
| 5 | [Security and operations](docs/05-security-and-operations.md) | Controls, monitoring, change management, audit roadmap |
| 6 | [Runbooks](docs/06-runbooks.md) | Add a guest, restore, onboard a user, domain join, patching, refresh docs |

## Scripts

| Script | Runs on | Purpose |
|---|---|---|
| [`proxmox-inventory.sh`](scripts/proxmox-inventory.sh) | Any Proxmox node | Cluster, storage, backup jobs, per-node network, every guest's config and IPs |
| [`Collect-HyperVInventory.ps1`](scripts/Collect-HyperVInventory.ps1) | Hyper-V host (admin) | Hardware, switches, VMs, VHDX chains, checkpoints, Secure Boot/TPM, integration services |
| [`Collect-DomainInventory.ps1`](scripts/Collect-DomainInventory.ps1) | Hyper-V host (admin) | Uses **PowerShell Direct** to query the DC: domain, forest, FSMO, replication, OUs, groups, GPO links, password policy, DNS, DHCP |

All three are **read-only** and safe to run against production systems.

## Skills demonstrated

**Systems:** Windows Server 2025 · Active Directory DS · Group Policy · DNS · Hyper-V · Proxmox VE (LXC/KVM) · Debian Linux · Docker · Proxmox Backup Server

**Cloud and identity:** Microsoft Entra ID · Entra Connect · Intune (MDM auto-enrollment) · hybrid join · AGDLP · least-privilege service accounts and API tokens

**Networking:** 802.1Q VLANs · network isolation · DHCP reservations · DNS filtering · VLAN-aware bridges · Tailscale subnet routing · RSTP

**Practices:** infrastructure documentation · read-only auditing · risk-ranked remediation planning · change logging · snapshot/checkpoint discipline · backup and restore procedures

**Automation:** PowerShell (including PowerShell Direct) · Bash · Proxmox REST API

