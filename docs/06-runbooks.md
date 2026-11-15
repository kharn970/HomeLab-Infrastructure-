# 6. Runbooks

[← Back to overview](../README.md)

Standard procedures for this environment.

## Add a new Proxmox guest

1. Pick the node by role: infrastructure on **pve**, applications on **pve3**, Windows, lab and backup workloads on **pve4**.
2. Create the guest on `local-lvm`, use an unprivileged container where possible, and set the bridge to `vmbr0` with the correct VLAN tag.
3. Give infrastructure services a static IP, then add a matching DHCP reservation in UniFi.
4. Set **Start at boot** and a startup order if other services depend on it.
5. Confirm the guest is covered by the nightly backup job.
6. Add the guest to the inventory and network documentation.

## Restore a Proxmox guest from backup

1. In the Proxmox UI, select the `BackupServer` storage on any node and open **Backups**.
2. Pick the guest and the restore point, then choose **Restore**.
3. Restore to a **new ID** first if you only need to recover files or want to compare, leaving the running guest untouched.
4. Start the restored guest with networking disconnected, verify it, then swap it in.
5. Record the restore and how long it took in the change log.

## Onboard a domain user

1. Create the account in `<Department>\Users`.
2. Add it to the department's **global role group**, never directly to resource groups.
3. If the role needs a resource, make sure the role group is nested into the right universal or domain local group (AGDLP).
4. Let Entra Connect sync the account (or run a delta sync), then assign licences in the cloud tenant.

## Join a Windows workstation to the domain

1. Set the workstation's DNS to the domain controllers.
2. Join `corp.example.com` with a delegated join account.
3. Move the computer object into `<Department>\Computers` so the department GPOs apply.
4. Run `gpupdate /force` and reboot. Confirm the sign-in banner appears and the device shows up in Intune.

## Patch cycle

1. Proxmox: patch one node at a time, migrate or shut down its guests, reboot, and confirm quorum before moving to the next node.
2. Windows: patch one DC at a time and confirm replication with `repadmin /replsummary` before patching the second.
3. Snapshot or checkpoint test machines before patching; never checkpoint domain controllers.

## Refresh the documentation

1. Proxmox: run [`scripts/proxmox-inventory.sh`](../scripts/proxmox-inventory.sh) on any node.
2. Hyper-V host: run [`scripts/Collect-HyperVInventory.ps1`](../scripts/Collect-HyperVInventory.ps1) as administrator.
3. Active Directory: run [`scripts/Collect-DomainInventory.ps1`](../scripts/Collect-DomainInventory.ps1) on the Hyper-V host. It queries the DC over PowerShell Direct.
4. Update the docs and close any remediated findings.
