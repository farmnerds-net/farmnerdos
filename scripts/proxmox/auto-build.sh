#!/usr/bin/env bash
# ONE-COMMAND FarmNerdOS pipeline for Proxmox VE. Run as root ON the PVE host:
#
#   ./auto-build.sh                    # farmlab defaults baked in
#
# What it does — zero console interaction:
#   1. extracts kernel/initrd from the stock Arch ISO (direct kernel boot)
#   2. serves the repo + payload over HTTP from this host
#   3. boots a build VM whose live env auto-runs the payload (script= cmdline)
#   4. receives the finished FarmNerdOS ISO back over HTTP, verifies sha256
#   5. installs it into ISO storage, destroys the build VM, boots the test VM
#
# Env overrides (defaults in brackets):
#   DISK_STORAGE [bigdisk_storage]  ISO_STORAGE [iso-storage]  BRIDGE [vmbr0]
#   ARCH_ISO [archlinux-2026.07.01-x86_64.iso]
#   BUILD_VMID [9001]  TEST_VMID [9000]  HTTP_PORT [8199]
#   HOST_IP [first addr of `hostname -I` — set explicitly on multi-homed hosts]
#   REPO_DIR [/root/farmnerdos]  TIMEOUT_MIN [90]  SKIP_TEST_VM [0]
set -euo pipefail

DISK_STORAGE="${DISK_STORAGE:-bigdisk_storage}"   # farmlab default
ISO_STORAGE="${ISO_STORAGE:-iso-storage}"         # farmlab default
BRIDGE="${BRIDGE:-vmbr0}"
ARCH_ISO="${ARCH_ISO:-archlinux-2026.07.01-x86_64.iso}"
BUILD_VMID="${BUILD_VMID:-9001}"
TEST_VMID="${TEST_VMID:-9000}"
HTTP_PORT="${HTTP_PORT:-8199}"
HOST_IP="${HOST_IP:-$(hostname -I | awk '{print $1}')}"
REPO_DIR="${REPO_DIR:-/root/farmnerdos}"
TIMEOUT_MIN="${TIMEOUT_MIN:-90}"
SKIP_TEST_VM="${SKIP_TEST_VM:-0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- preflight ----------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "run as root on the PVE host"
command -v qm >/dev/null || die "qm not found — is this a PVE host?"
command -v python3 >/dev/null || die "python3 not found"
pvesm status --storage "$DISK_STORAGE" >/dev/null 2>&1 \
    || { echo "Available storages:"; pvesm status; die "storage '$DISK_STORAGE' not found"; }
[[ -d $REPO_DIR ]] || die "repo not found at $REPO_DIR (scp it in first)"
qm status "$BUILD_VMID" >/dev/null 2>&1 && die "VMID $BUILD_VMID exists — destroy it or set BUILD_VMID"
if [[ $SKIP_TEST_VM != 1 ]]; then
    qm status "$TEST_VMID" >/dev/null 2>&1 && die "VMID $TEST_VMID exists — destroy it or set TEST_VMID"
fi

ARCH_ISO_PATH="$(pvesm path "$ISO_STORAGE:iso/$ARCH_ISO" 2>/dev/null)" || die "cannot resolve $ARCH_ISO"
[[ -f $ARCH_ISO_PATH ]] || die "$ARCH_ISO not on '$ISO_STORAGE'"

# --- stage: kernel, initrd, repo tarball, payload ------------------------------
STAGE="$(mktemp -d /tmp/farmnerdos-auto.XXXXXX)"
HTTP_PID=""
cleanup() {
    [[ -n $HTTP_PID ]] && kill "$HTTP_PID" 2>/dev/null || true
    mountpoint -q "$STAGE/isomnt" && umount "$STAGE/isomnt" || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$STAGE/http/incoming" "$STAGE/isomnt"
ISO_LABEL="$(blkid -o value -s LABEL "$ARCH_ISO_PATH")"
[[ -n $ISO_LABEL ]] || die "could not read ISO volume label"
echo "==> stock ISO label: $ISO_LABEL"

mount -o loop,ro "$ARCH_ISO_PATH" "$STAGE/isomnt"
cp "$STAGE/isomnt/arch/boot/x86_64/vmlinuz-linux" \
   "$STAGE/isomnt/arch/boot/x86_64/initramfs-linux.img" "$STAGE/http/"
umount "$STAGE/isomnt"

echo "==> packaging repo"
tar czf "$STAGE/http/farmnerdos.tar.gz" \
    --exclude='work' --exclude='out' --exclude='.git' --exclude='repo/x86_64' \
    -C "$(dirname "$REPO_DIR")" "$(basename "$REPO_DIR")"
cp "$HERE/live-build.sh" "$STAGE/http/live-build.sh"

echo "==> serving on http://$HOST_IP:$HTTP_PORT"
python3 "$HERE/httpserv.py" "$HTTP_PORT" "$STAGE/http" &
HTTP_PID=$!
sleep 1
curl -sf -o /dev/null "http://$HOST_IP:$HTTP_PORT/live-build.sh" \
    || die "HTTP self-check failed — is $HOST_IP reachable / port $HTTP_PORT free?"

# --- build VM: direct kernel boot with automation cmdline ----------------------
# dir-type storages need explicit raw format so the payload sees a plain disk
STYPE="$(pvesm status --storage "$DISK_STORAGE" | awk 'NR==2{print $2}')"
SCRATCH="$DISK_STORAGE:64"
case "$STYPE" in dir|nfs|cifs) SCRATCH="$SCRATCH,format=raw";; esac

APPEND="archisobasedir=arch archisolabel=$ISO_LABEL cow_spacesize=6G"
APPEND+=" script=http://$HOST_IP:$HTTP_PORT/live-build.sh"
APPEND+=" farm_http=http://$HOST_IP:$HTTP_PORT"

echo "==> creating build VM $BUILD_VMID"
qm create "$BUILD_VMID" \
    --name farmnerdos-autobuild \
    --machine q35 --cores 8 --cpu host --memory 12288 --balloon 0 \
    --scsihw virtio-scsi-single --scsi0 "$SCRATCH,iothread=1" \
    --net0 "virtio,bridge=$BRIDGE" \
    --cdrom "$ISO_STORAGE:iso/$ARCH_ISO" \
    --ostype l26 --vga std \
    --args "-kernel $STAGE/http/vmlinuz-linux -initrd $STAGE/http/initramfs-linux.img -append '$APPEND'"

qm start "$BUILD_VMID"
echo "==> build VM running — waiting for ISO upload (timeout ${TIMEOUT_MIN}m)"
echo "    log arrives at: $STAGE/http/incoming/build.log (on completion/failure)"

# --- wait for result ------------------------------------------------------------
DEADLINE=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
RESULT_ISO=""
while (( $(date +%s) < DEADLINE )); do
    if [[ -f "$STAGE/http/incoming/FAILED" ]]; then
        echo "---- build.log (tail) ----"
        tail -30 "$STAGE/http/incoming/build.log" 2>/dev/null || true
        die "build FAILED — VM $BUILD_VMID left running for console inspection"
    fi
    RESULT_ISO="$(ls "$STAGE"/http/incoming/farmnerdos-*.iso 2>/dev/null | head -1 || true)"
    [[ -n $RESULT_ISO && -f "$RESULT_ISO.sha256" ]] && break
    sleep 15
done
[[ -n $RESULT_ISO ]] || die "timed out — check VM $BUILD_VMID console"

echo "==> verifying checksum"
# compare hashes directly — robust to path-ful checksum files, and never
# let the cleanup trap eat a good ISO over a verification hiccup
EXPECTED="$(awk '{print $1}' "$RESULT_ISO.sha256")"
ACTUAL="$(sha256sum "$RESULT_ISO" | awk '{print $1}')"
if [[ -z $EXPECTED || $EXPECTED != "$ACTUAL" ]]; then
    SAVED="/var/tmp/$(basename "$RESULT_ISO")"
    mv "$RESULT_ISO" "$SAVED"
    die "sha256 mismatch on uploaded ISO — unverified copy saved at $SAVED"
fi

# --- install ISO, tear down build VM -------------------------------------------
OUT_NAME="$(basename "$RESULT_ISO")"
DEST="$(pvesm path "$ISO_STORAGE:iso/$OUT_NAME")"
mv "$RESULT_ISO" "$DEST"
echo "==> ISO installed: $ISO_STORAGE:iso/$OUT_NAME"

# wait for the payload's poweroff, then destroy
for _ in $(seq 1 40); do
    [[ "$(qm status "$BUILD_VMID" | awk '{print $2}')" == stopped ]] && break
    sleep 5
done
qm stop "$BUILD_VMID" 2>/dev/null || true
qm destroy "$BUILD_VMID" --purge
echo "==> build VM destroyed"

# --- test VM ---------------------------------------------------------------------
if [[ $SKIP_TEST_VM == 1 ]]; then
    echo "==> SKIP_TEST_VM=1 — done. Boot it later with:"
    echo "    FARM_ISO=$OUT_NAME $HERE/create-test-vm.sh $TEST_VMID"
    exit 0
fi
DISK_STORAGE="$DISK_STORAGE" ISO_STORAGE="$ISO_STORAGE" BRIDGE="$BRIDGE" \
    FARM_ISO="$OUT_NAME" "$HERE/create-test-vm.sh" "$TEST_VMID"
echo "==> pipeline complete: FarmNerdOS Seedling is booting in VM $TEST_VMID"
