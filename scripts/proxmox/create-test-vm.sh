#!/usr/bin/env bash
# Create the FarmNerdOS *test* VM on a Proxmox VE host and boot the built ISO.
#
# Run ON the PVE host:
#   ./create-test-vm.sh [vmid]        # farmlab defaults baked in
#
# Env overrides:
#   DISK_STORAGE  VM disk storage             (default: bigdisk_storage)
#   ISO_STORAGE   ISO storage                 (default: iso-storage)
#   BRIDGE        network bridge              (default: vmbr0)
#   FARM_ISO      FarmNerdOS ISO filename     (default: newest farmnerdos-*.iso by mtime)
#   FIRMWARE      uefi | bios                 (default: uefi — test both before release!)
#   CORES / MEM_MB / DISK_GB                  (default: 4 / 8192 / 40)
set -euo pipefail

VMID="${1:-9000}"
DISK_STORAGE="${DISK_STORAGE:-bigdisk_storage}"   # farmlab default
ISO_STORAGE="${ISO_STORAGE:-iso-storage}"         # farmlab default
BRIDGE="${BRIDGE:-vmbr0}"
FIRMWARE="${FIRMWARE:-uefi}"
CORES="${CORES:-4}"
MEM_MB="${MEM_MB:-8192}"
DISK_GB="${DISK_GB:-40}"

command -v qm >/dev/null || { echo "error: qm not found — run this on the PVE host"; exit 1; }
pvesm status --storage "$DISK_STORAGE" >/dev/null 2>&1 || {
    echo "error: storage '$DISK_STORAGE' not found. Available:"; pvesm status; exit 1; }

if [[ -z "${FARM_ISO:-}" ]]; then
    # newest by file mtime — NOT lexicographic (date-versioned names like
    # farmnerdos-2026.07.12 would otherwise beat farmnerdos-0.1-seedling)
    newest=""
    while read -r name; do
        p="$(pvesm path "$ISO_STORAGE:iso/$name" 2>/dev/null)" || continue
        if [[ -f $p && ( -z $newest || $p -nt $newest ) ]]; then
            newest="$p"; FARM_ISO="$name"
        fi
    done < <(pvesm list "$ISO_STORAGE" --content iso | grep -oE 'farmnerdos[^ ]*\.iso' || true)
    [[ -n "${FARM_ISO:-}" ]] || { echo "error: no farmnerdos-*.iso on '$ISO_STORAGE' — build it first"; exit 1; }
fi
echo "==> using ISO: $FARM_ISO"

qm status "$VMID" >/dev/null 2>&1 && { echo "error: VMID $VMID already exists"; exit 1; }

echo "==> creating test VM $VMID (firmware=$FIRMWARE, storage=$DISK_STORAGE)"
qm create "$VMID" \
    --name farmnerdos-seedling \
    --machine q35 \
    --cores "$CORES" --cpu host \
    --memory "$MEM_MB" --balloon 2048 \
    --scsihw virtio-scsi-single \
    --scsi0 "$DISK_STORAGE:$DISK_GB,iothread=1,discard=on" \
    --net0 "virtio,bridge=$BRIDGE" \
    --cdrom "$ISO_STORAGE:iso/$FARM_ISO" \
    --boot order='ide2;scsi0' \
    --ostype l26 \
    --vga virtio \
    --agent enabled=1

if [[ $FIRMWARE == uefi ]]; then
    # pre-enrolled-keys=0 is REQUIRED: Secure Boot's MS keys would reject our
    # unsigned kernel/bootloader and the ISO would not boot.
    qm set "$VMID" --bios ovmf --efidisk0 "$DISK_STORAGE:1,efitype=4m,pre-enrolled-keys=0"
fi

qm start "$VMID"
echo "==> FarmNerdOS test VM $VMID started — open the console. Expect:"
echo "    SDDM autologin -> farmer @ Plasma (dark + green), linux-cachyos kernel,"
echo "    'Install FarmNerdOS' icon on the desktop."
echo "    Verify kernel:   uname -r        (should end in -cachyos)"
echo "    Verify agent:    qm agent $VMID ping   (from PVE host, after boot)"
