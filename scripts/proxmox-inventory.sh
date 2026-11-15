#!/usr/bin/env bash
# proxmox-inventory.sh
# Read-only inventory of a Proxmox VE cluster. Run as root in the shell of any one node.
# Collects version, cluster state, storage, backup jobs, SDN, and per-node network plus
# every container's and VM's configuration and IP addresses. Changes nothing.
# Output: /root/homelab-inventory.txt
{
ids() { perl -MJSON -e 'print "$_->{'"$1"'}\n" for @{decode_json(join "", <STDIN>)}'; }
echo "### VERSION";  pveversion
echo "### CLUSTER";  pvecm status
echo "### RESOURCES"; pvesh get /cluster/resources --output-format json
echo "### STORAGE";  cat /etc/pve/storage.cfg
echo "### BACKUP JOBS"; cat /etc/pve/jobs.cfg 2>/dev/null
echo "### SDN"; cat /etc/pve/sdn/*.cfg 2>/dev/null
for n in $(pvesh get /nodes --output-format json | ids node); do
  echo "### NODE $n NETWORK"; pvesh get /nodes/$n/network --output-format json
  echo "### NODE $n STATUS";  pvesh get /nodes/$n/status --output-format json
  for id in $(pvesh get /nodes/$n/lxc --output-format json | ids vmid); do
    echo "### CT $id CONFIG"; pvesh get /nodes/$n/lxc/$id/config --output-format json
    echo "### CT $id IPS";    pvesh get /nodes/$n/lxc/$id/interfaces --output-format json 2>/dev/null
  done
  for id in $(pvesh get /nodes/$n/qemu --output-format json | ids vmid); do
    echo "### VM $id CONFIG"; pvesh get /nodes/$n/qemu/$id/config --output-format json
  done
done
} > /root/homelab-inventory.txt 2>&1
echo "Saved to /root/homelab-inventory.txt"
