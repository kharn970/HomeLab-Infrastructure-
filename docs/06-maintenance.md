# 6. Operations and maintenance

[← Back to overview](../README.md)

How the environment is kept consistent, patched, recoverable and documented.

## Build standards

Every new workload is held to the same baseline, so the environment stays predictable as it grows.

| Standard | Applied as |
|---|---|
| Placement by role | Infrastructure on **pve**, applications on **pve3**, Windows, lab and backup workloads on **pve4** |
| Isolation | Unprivileged LXC containers by default; VMs only where a full kernel or Windows is required |
| Networking | VLAN-aware `vmbr0` bridge with the guest tagged into its segment (in place on pve4; pve and pve3 are on the [roadmap](05-security-and-operations.md#audit-and-remediation-roadmap)); infrastructure services on static IPs with matching DHCP reservations |
| Protection | Covered by the nightly backup job automatically; exclusions are deliberate and limited to lab or disposable guests |
| Identity | Users and computers placed in department OUs; access granted through role groups only (AGDLP) |
| Documentation | Inventory, network plan and changelog updated as part of the change, not after it |

## Patch management

| Platform | Approach |
|---|---|
| Proxmox VE | Rolling updates, one node at a time; guests migrated or stopped, cluster quorum confirmed before moving to the next node |
| Windows Server | One domain controller at a time; AD replication health verified before the second DC is patched |
| Test machines | Snapshot or checkpoint taken before patching; domain controllers are never checkpointed |

## Backup verification and recovery

- The nightly job is verified every morning by an automated report that compares each guest the job is configured to protect against the job's actual log, so a skipped or failed guest is surfaced the same day.
- Exclusions are read straight from the Proxmox job definition, so the report and the backup policy cannot drift apart.
- Restores go to a new guest ID first and are validated with networking disconnected before replacing the original, so a recovery never puts the running service at risk.

## Monitoring-driven maintenance

Maintenance work is driven by data rather than routine checks. The [n8n workflows](05-security-and-operations.md#automated-monitoring-n8n) alert on stopped guests, capacity thresholds and backup problems, and every alert either becomes a fix or a tracked item on the [remediation roadmap](05-security-and-operations.md#audit-and-remediation-roadmap).

## Documentation as code

The documentation is regenerated from the systems themselves rather than maintained by hand:

| Source | Collected by |
|---|---|
| Proxmox cluster, storage, backup jobs and every guest | [`proxmox-inventory.sh`](../scripts/proxmox-inventory.sh) and a weekly n8n workflow that diffs the inventory against the previous week |
| Hyper-V host, VMs, disks and checkpoints | [`Collect-HyperVInventory.ps1`](../scripts/Collect-HyperVInventory.ps1) |
| Active Directory, GPOs, DNS and DHCP | [`Collect-DomainInventory.ps1`](../scripts/Collect-DomainInventory.ps1) over PowerShell Direct |

All collectors are read-only. Changes they detect are reviewed, reflected in the docs and recorded in the [changelog](../CHANGELOG.md).
