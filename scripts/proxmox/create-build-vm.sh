#!/usr/bin/env bash
# Create the throwaway FarmNerdOS *build* VM on a Proxmox VE host (MANUAL mode;
# auto-build.sh does all of this unattended). It boots the STOCK Arch ISO; the
# FarmNerdOS ISO is built inside the live environment on a scratch disk.
#
# Run ON the PVE host:
#   ./create-build-vm.sh [vmid]       # farmlab defaults baked in
#
# Env overrides:
#   DISK_STORAGE  VM disk storage            (default: bigdisk_storage)
#   ISO_STORAGE   ISO storage                (default: iso-storage)
#   BRIDGE        network bridge             (default: vmbr0)
#   ARCH_ISO      stock Arch ISO filename    (default: archlinux-2026.07.01-x86_64.iso)
#   CORES / MEM_MB / SCRATCH_GB              (default: 8 / 12288 / 64)
set -euo pipefail

VMID="${1:-9001}"
DISK_STORAGE="${DISK_STORAGE:-bigdisk_storage}"   # farmlab default
ISO_STORAGE="${ISO_STORAGE:-iso-storage}"         # farmlab default
BRIDGE="${BRIDGE:-vmbr0}"
ARCH_ISO="${ARCH_ISO:-archlinux-2026.07.01-x86_64.iso}"
CORES="${CORES:-8}"
MEM_MB="${MEM_MB:-12288}"
SCRATCH_GB="${SCRATCH_GB:-64}"

command -v qm >/dev/null || { echo "error: qm not found — run this on the PVE host"; exit 1; }

pvesm status --storage "$DISK_STORAGE" >/dev/null 2>&1 || {
    echo "error: storage '$DISK_STORAGE' not found. Available:"; pvesm status; exit 1; }

pvesm list "$ISO_STORAGE" --content iso | grep -q "$ARCH_ISO" || {
    echo "error: $ARCH_ISO not on '$ISO_STORAGE'. Upload it first, e.g. from your PC:"
    echo "  scp archlinux-2026.07.01-x86_64.iso root@10.30.2.2:/path/to/iso-storage/template/iso/"
    exit 1; }

qm status "$VMID" >/dev/null 2>&1 && { echo "error: VMID $VMID already exists"; exit 1; }

echo "==> creating build VM $VMID (storage=$DISK_STORAGE)"
qm create "$VMID" \
    --name farmnerdos-build \
    --machine q35 \
    --cores "$CORES" --cpu host \
    --memory "$MEM_MB" --balloon 0 \
    --scsihw virtio-scsi-single \
    --scsi0 "$DISK_STORAGE:$SCRATCH_GB,iothread=1" \
    --net0 "virtio,bridge=$BRIDGE" \
    --cdrom "$ISO_STORAGE:iso/$ARCH_ISO" \
    --boot order='ide2;scsi0' \
    --ostype l26 \
    --vga std \
    --agent enabled=0

qm start "$VMID"
echo "==> build VM $VMID started."
cat <<'NEXT'

Next steps:
  1. Open the VM console (PVE UI), let the Arch live env boot to the root prompt.
  2. In the live env:  passwd   then   ip -4 addr show   (note the IP)
  3. From your PC:     scp -r farmnerdos root@<build-vm-ip>:/root/
  4. In the VM:        bash /root/farmnerdos/scripts/proxmox/bootstrap-build.sh
  5. It prints the scp command that pushes the finished ISO to your ISO storage.
     Then destroy this VM:  qm stop 9001 && qm destroy 9001 --purge
NEXT
