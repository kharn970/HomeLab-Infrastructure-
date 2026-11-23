# 5. Security and operations

[← Back to overview](../README.md)

## Security controls in place

| Area | Control |
|---|---|
| Perimeter | No inbound port forwards to internal networks; remote access only through Tailscale. Honeypot ports forward only to the DMZ firewall |
| Segmentation | 4 VLANs; honeypot DMZ behind two independent firewall layers (UniFi zone policies and pfSense), with the sensor on separate hardware |
| Detection | Suricata IDS (ET Open) on the DMZ firewall and on the honeypot sensor; firewall tripwire rules log any DMZ attempt to reach a private address |
| Egress | DMZ limited to HTTP/HTTPS outbound, rate-limited to 10 Mbit/s, logged default deny |
| DNS | Network-wide filtering through AdGuard Home |
| Least privilege | Read-only auditor account for documentation; scoped API tokens for monitoring and backup; Domain, Enterprise and Schema Admins limited to a single admin account |
| Identity | AGDLP group model, department OUs, pre-logon legal banner by GPO, Intune enrollment |
| Endpoints | Windows 11 VMs on UEFI with Secure Boot and vTPM 2.0 |
| Containers | All LXC containers unprivileged |
| Data | End-to-end encrypted note sync |
| Switching | RSTP, rogue DHCP server detection, DHCP guarding on the DMZ VLAN |

## Monitoring

- **Pulse** dashboard for node, guest and storage health across the cluster.
- **UniFi** client and device monitoring, plus a daily WAN speed test.
- Backup job notifications through the Proxmox notification system.

### Automated monitoring (n8n)

Five n8n workflows poll the Proxmox REST API with a read-only API token and report to a private Discord channel:

| Workflow | Schedule | Alerts on |
|---|---|---|
| Daily backup report | Daily 07:00 | Compares the guests each backup job is configured to protect against the job's log; reports any that failed or were skipped, plus datastore usage |
| Guests down check | Every 15 min | A guest that should always run stops, or a node goes offline; alerts once on change and again on recovery |
| Disk space watch | Every 6 h | Storage pools, node root disks and container disks crossing 80/90% (containers 85/95%), plus a Monday summary |
| Weekly docs update | Sundays 06:00 | Regenerates the infrastructure inventory from the API and reports what changed since the previous week |
| Weekly GitHub changelog | Sundays 06:30 | Publishes the lab change log from the internal documentation share to this repository's [changelog](../CHANGELOG.md); lines containing IP addresses are held back, and nothing is committed when there are no new entries |

State (what was already reported) is kept in workflow static data so alerts fire on changes, not every run. The first runs caught a VM whose backups had silently failed for 29 days and a node running its backup window in the wrong time zone.

## Change management

Each managed system has a documentation page with a dated change log. Before a risky change, the guest is snapshotted (Proxmox) or checkpointed (Hyper-V). After the change, the documentation and the remediation tracker are updated.

## Audit and remediation roadmap

Findings from the latest read-only audit, prioritized:

| Priority | Finding | Remediation |
|---|---|---|
| High | Hyper-V host runs Windows 10 22H2, past end of support (October 2025), and hosts both domain controllers | Move the host to a supported OS (Windows 11 Pro or Windows Server with Hyper-V), or cover it with Extended Security Updates until then |
| High | Backups stored on a single disk in one node | Add off-node replication of the PBS datastore |
| High | FSMO-holding DC VM running on an old checkpoint | Merge the checkpoint; disable checkpoints on all DC VMs |
| High | DNS role on only one DC | Install DNS on the second DC; DCs point only at each other for DNS |
| Medium | Hyper-V time synchronization enabled on DC VMs | Disable for DCs; PDC Emulator syncs to external NTP |
| Medium | AD Recycle Bin not enabled | Enable the Recycle Bin |
| Medium | Several services start manually after a node reboot | Enable start-at-boot with startup ordering |
| Medium | Some services on dynamic DHCP addresses | Add DHCP reservations |
| Medium | Mixed Proxmox patch levels across nodes | Patch to a common release during a maintenance window |
| Low | One workstation in the default Computers container (misses OU GPOs) | Move it to its department OU; redirect the default container |
| Low | Evaluation licences on the Windows Server VMs | Track expiry; convert or rebuild before it lapses |
| Medium | Non-VLAN-aware bridges on pve and pve3 flood every tagged VLAN from the switch trunk to their guests (VLAN 99 broadcasts seen inside a guest) | Limit the switch port profiles to the VLANs those nodes need, or make `vmbr0` VLAN-aware with explicit allowed VLANs |
| Medium | The pfSense VM is still excluded from nightly backups from its lab days | Re-include it now that it is the DMZ firewall; keep an offline configuration export |
| Low | The DMZ firewall VM is not on the stopped-guest alert list | Add it to the n8n guests-down workflow |
| Low | The security tooling VM is tagged for VLAN 3 but receives a Default-network address | Check VLAN carriage on that node's switch port; move the VM to its intended segment |
