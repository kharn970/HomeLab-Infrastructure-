# 1. Network

[← Back to overview](../README.md)

## Topology

```mermaid
flowchart LR
  ISP["Fiber ISP<br/>2.5 GbE WAN"] --> GW["UniFi Cloud Gateway Ultra<br/>routing · firewall · DHCP"]
  GW -->|port 3| PC["Admin workstation"]
  GW -->|port 2| MESH["Wi-Fi mesh (VLAN 3)"]
  GW --> SW["UniFi Switch Lite 8 PoE"]
  SW -->|port 2| N1["Proxmox node pve"]
  SW -->|port 3| N3["Proxmox node pve3"]
  SW -->|port 5| N4["Proxmox node pve4<br/>VLAN-aware bridge"]
  GW -.-> HV["Hyper-V host (VLAN 2)"]
```

| Device | Role |
|---|---|
| UniFi Cloud Gateway Ultra | Edge router, stateful firewall, DHCP server for every VLAN, inter-VLAN routing |
| UniFi Switch Lite 8 PoE | Access switch for the Proxmox cluster; RSTP enabled, rogue DHCP detection on |
| Wi-Fi mesh (2 units) | Wireless access on its own VLAN |

WAN is a single fiber circuit with a second WAN port reserved for failover. UPnP is disabled.

## VLANs

| VLAN | Name | Subnet | Gateway | DHCP pool | Isolated | Purpose |
|---|---|---|---|---|---|---|
| 1 | Default | 192.168.1.0/24 | .1 | .6 to .254 | No | Proxmox nodes, Linux services, wired PCs |
| 2 | Windows Server | 192.168.2.0/24 | .1 | .6 to .254 | No | Hyper-V host, Active Directory, Windows clients |
| 3 | Wi-Fi | 192.168.3.0/24 | .1 | .6 to .254 | No | Wireless clients, security tooling VM |
| 4 | Isolated | 192.168.4.0/24 | .1 | .6 to .254 | **Yes** | Honeypot VM (in progress) |
| 99 | DMZ | 192.168.99.0/28 | .1 | .6 to .14 | **DMZ zone** | WAN side of the pfSense honeypot firewall ([section 7](07-dmz-honeypot.md)) |

"Isolated" uses UniFi's per-network isolation: hosts on VLAN 4 can reach the internet but no other internal network. VLAN 99 is in UniFi's **DMZ zone** with explicit zone policies instead: the DMZ can only reply to internal hosts, and only the admin workstation can reach it. DHCP guarding is enabled on both VLANs.

VLAN tags reach VMs through a VLAN-aware Linux bridge on Proxmox (`vmbr0` on pve4, guest NICs tagged 2, 3 or 99) and through access-mode VLAN assignment on Hyper-V virtual NICs.

## IP addressing policy

- **Infrastructure** (hypervisors, DNS, monitoring, backup, file services, domain controllers) uses static addresses that are also reserved in UniFi, so DHCP can never hand them out twice.
- **Application services** get DHCP reservations, so addresses survive lease expiry and rebuilds.
- **Clients** use dynamic DHCP from the gateway's pool for their VLAN.
- Low addresses in each subnet are kept outside the DHCP pool for network equipment.

## DNS

```mermaid
flowchart LR
  C["Client (any VLAN)"] -->|DHCP-assigned DNS| G["Gateway"]
  G -->|upstream DNS| A["AdGuard Home"]
  A --> U["Public resolvers"]
  D["Domain members (VLAN 2)"] --> DC["AD-integrated DNS<br/>on the domain controller"]
```

- Every DHCP client uses its VLAN gateway for DNS. The gateway's own upstream is AdGuard Home, so all networks are filtered without configuring individual devices.
- Active Directory members resolve `corp.example.com` through AD-integrated DNS on the domain controllers.
- Proxmox nodes use the gateway; the subnet-router node uses Tailscale MagicDNS.

## Remote access

Remote administration uses a **Tailscale** mesh VPN instead of port forwarding, so no inbound ports lead to any internal network. The only port forwards on the gateway carry honeypot traffic to the DMZ firewall ([section 7](07-dmz-honeypot.md)), and the DMZ ranges are not advertised to the tailnet.

- One Proxmox node is the **subnet router**, publishing the LAN to authorized tailnet devices.
- MagicDNS and HTTPS certificates are enabled for tailnet hostnames.
- Server nodes have key expiry disabled; user devices keep expiring keys and re-authenticate.
