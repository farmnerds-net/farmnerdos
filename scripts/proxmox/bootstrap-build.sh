#!/usr/bin/env bash
# Build FarmNerdOS from INSIDE the stock Arch live environment (MANUAL mode).
# Expects the repo at /root/farmnerdos (scp'd in) and a blank scratch disk.
#
#   bash /root/farmnerdos/scripts/proxmox/bootstrap-build.sh
set -euo pipefail

SCRATCH_DEV="${SCRATCH_DEV:-/dev/sda}"   # the 64G virtio-scsi scratch disk
BUILD=/build
REPO_SRC=/root/farmnerdos

[[ $EUID -eq 0 ]] || { echo "error: run as root (live env default)"; exit 1; }
[[ -d $REPO_SRC ]] || { echo "error: $REPO_SRC missing — scp the repo in first"; exit 1; }
[[ -b $SCRATCH_DEV ]] || { echo "error: scratch disk $SCRATCH_DEV not found"; lsblk; exit 1; }

# refuse to eat a disk that already has partitions/filesystem signatures
if [[ -n "$(lsblk -no FSTYPE,PARTTYPE "$SCRATCH_DEV" | tr -d '[:space:]')" ]]; then
    echo "error: $SCRATCH_DEV is not blank — refusing to format. Set SCRATCH_DEV explicitly."
    lsblk -f "$SCRATCH_DEV"; exit 1
fi

echo "==> preparing scratch disk"
mkfs.ext4 -q -L farmbuild "$SCRATCH_DEV"
mkdir -p "$BUILD"
mount "$SCRATCH_DEV" "$BUILD"

echo "==> growing live cowspace (pacman installs need room)"
mount -o remount,size=6G /run/archiso/cowspace

echo "==> installing build dependencies (package cache on scratch disk)"
mkdir -p "$BUILD/pkgcache"
pacman -Sy --noconfirm --needed --cachedir "$BUILD/pkgcache" \
    git base-devel archiso

echo "==> staging repo on scratch disk"
cp -a "$REPO_SRC" "$BUILD/farmnerdos"
# exec bits don't survive the Windows->scp trip; restore, and invoke via bash
chmod +x "$BUILD"/farmnerdos/scripts/*.sh "$BUILD"/farmnerdos/scripts/proxmox/*.sh \
         "$BUILD"/farmnerdos/iso/profiledef.sh 2>/dev/null || true

echo "==> creating unprivileged builder (makepkg refuses root)"
useradd -m builder 2>/dev/null || true
chown -R builder:builder "$BUILD/farmnerdos"

echo "==> building FarmNerdOS packages"
su builder -c "bash $BUILD/farmnerdos/scripts/build-packages.sh"

echo "==> building FarmNerdOS ISO (this is the long part)"
bash "$BUILD/farmnerdos/scripts/build-iso.sh"

ISO_PATH="$(ls "$BUILD"/farmnerdos/out/*.iso)"
echo
echo "==> SUCCESS: $ISO_PATH"
echo
echo "Push it to your PVE ISO storage (from this VM):"
echo "  scp $ISO_PATH root@10.30.2.2:\$(ssh root@10.30.2.2 pvesm path iso-storage:iso/x 2>/dev/null | xargs dirname 2>/dev/null || echo /var/lib/vz/template/iso)/"
echo "  (or simply: scp $ISO_PATH root@10.30.2.2:/tmp/ and move it on the host)"
echo
echo "Then on the PVE host, create the test VM:"
echo "  ./create-test-vm.sh"
