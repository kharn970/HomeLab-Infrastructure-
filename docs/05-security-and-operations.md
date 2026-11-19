# 5. Security and operations

[← Back to overview](../README.md)

## Security controls in place

| Area | Control |
|---|---|
| Perimeter | No inbound port forwards; remote access only through Tailscale |
| Segmentation | 5 VLANs; honeypot and lab-WAN networks isolated from all internal networks |
| DNS | Network-wide filtering through AdGuard Home |
| Least privilege | Read-only auditor account for documentation; scoped API tokens for monitoring and backup; Domain, Enterprise and Schema Admins limited to a single admin account |
| Identity | AGDLP group model, department OUs, pre-logon legal banner by GPO, Intune enrollment |
| Endpoints | Windows 11 VMs on UEFI with Secure Boot and vTPM 2.0 |
| Containers | All LXC containers unprivileged |
| Data | End-to-end encrypted note sync |
| Switching | RSTP, rogue DHCP server detection, DHCP guarding on isolated VLANs |

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
| Weekly GitHub changelog | Sundays 06:30 | Commits a sanitized summary of the week's guest changes to this repository's [changelog](../CHANGELOG.md); skipped when nothing changed |

State (what was already reported) is kept in workflow static data so alerts fire on changes, not every run. The first runs caught a VM whose backups had silently failed for 29 days and a node running its backup window in the wrong time zone.

## Change management

Each managed system has a documentation page with a dated change log. Before a risky change, the guest is snapshotted (Proxmox) or checkpointed (Hyper-V). After the change, the documentation and the remediation tracker are updated.

## Audit and remediation roadmap

Findings from the latest read-only audit, prioritized:

| Priority | Finding | Remediation |
|---|---|---|
| High | Backups stored on a single disk in one node | Add off-node replication of the PBS datastore |
| High | FSMO-holding DC VM running on an old checkpoint | Merge the checkpoint; disable checkpoints on all DC VMs |
| High | DNS role on only one DC | Install DNS on the second DC; DCs point only at each other for DNS |
| Medium | Hyper-V time synchronization enabled on DC VMs | Disable for DCs; PDC Emulator syncs to external NTP |
| Medium | AD Recycle Bin not enabled | Enable the Recycle Bin |
| Medium | Several services start manually after a node reboot | Enable start-at-boot with startup ordering |
| Medium | Some services on dynamic DHCP addresses | Add DHCP reservations |
| Medium | Mixed Proxmox patch levels across nodes | Patch to a common release during a maintenance window |
| Low | One workstation in the default Computers container (misses OU GPOs) | Move it to its department OU; redirect the default container |
| Low | DC hostname longer than 15 characters (NetBIOS truncation) | Use 15-character names for future DCs |
| Low | Evaluation licences on the Windows Server VMs | Track expiry; convert or rebuild before it lapses |
