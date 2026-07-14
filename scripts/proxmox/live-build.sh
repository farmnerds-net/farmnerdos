#!/usr/bin/env bash
# PAYLOAD — runs automatically inside the stock Arch live environment.
# Delivered via the `script=` kernel parameter; do not run by hand on real HW.
# Fetches the repo from the PVE host, builds the FarmNerdOS ISO on the scratch
# disk, uploads the result back over HTTP, then powers off.
set -euo pipefail

FARM_HTTP="$(grep -oE 'farm_http=[^ ]+' /proc/cmdline | cut -d= -f2-)"
[[ -n $FARM_HTTP ]] || { echo "FATAL: farm_http= missing from kernel cmdline"; exit 1; }

SCRATCH_DEV="${SCRATCH_DEV:-/dev/sda}"
BUILD=/build
LOG=/tmp/farmnerdos-build.log

fail() {
    echo "BUILD FAILED: $1" | tee -a "$LOG"
    curl -sf -T "$LOG" "$FARM_HTTP/build.log" || true
    echo "FAILED: $1" > /tmp/FAILED
    curl -sf -T /tmp/FAILED "$FARM_HTTP/FAILED" || true
    exit 1   # VM left running for console inspection
}
trap 'fail "line $LINENO"' ERR

exec > >(tee -a "$LOG") 2>&1
echo "==> FarmNerdOS automated build starting ($(date -u +%FT%TZ))"

# wait for DHCP (systemd-networkd in the live env)
for _ in $(seq 1 30); do
    curl -sf -o /dev/null "$FARM_HTTP/live-build.sh" && break
    sleep 2
done
curl -sf -o /dev/null "$FARM_HTTP/live-build.sh" || fail "cannot reach $FARM_HTTP"

echo "==> preparing scratch disk $SCRATCH_DEV"
[[ -b $SCRATCH_DEV ]] || fail "scratch disk missing"
wipefs -aq "$SCRATCH_DEV"        # disk is created fresh by the orchestrator
mkfs.ext4 -q -L farmbuild "$SCRATCH_DEV"
mkdir -p "$BUILD" && mount "$SCRATCH_DEV" "$BUILD"

echo "==> fetching repo"
curl -sf "$FARM_HTTP/farmnerdos.tar.gz" -o "$BUILD/repo.tar.gz" || fail "repo fetch"
tar xzf "$BUILD/repo.tar.gz" -C "$BUILD"
# exec bits don't survive the Windows->scp->tar trip; restore them and invoke
# every script via `bash` anyway (belt and braces)
chmod +x "$BUILD"/farmnerdos/scripts/*.sh "$BUILD"/farmnerdos/scripts/proxmox/*.sh \
         "$BUILD"/farmnerdos/iso/profiledef.sh 2>/dev/null || true

echo "==> installing build dependencies"
mkdir -p "$BUILD/pkgcache"
pacman -Sy --noconfirm --needed --cachedir "$BUILD/pkgcache" \
    git base-devel archiso || fail "dependency install"

echo "==> building packages (unprivileged)"
useradd -m builder 2>/dev/null || true
chown -R builder:builder "$BUILD/farmnerdos"
su builder -c "bash $BUILD/farmnerdos/scripts/build-packages.sh" || fail "package build"

echo "==> building ISO"
bash "$BUILD/farmnerdos/scripts/build-iso.sh" || fail "mkarchiso"

ISO_FILE="$(ls "$BUILD"/farmnerdos/out/*.iso | head -1)"
# checksum must reference the BASENAME — the verifier runs on the PVE host
# where the build path does not exist
( cd "$(dirname "$ISO_FILE")" && sha256sum "$(basename "$ISO_FILE")" > "$ISO_FILE.sha256" )

echo "==> uploading $(basename "$ISO_FILE") ($(du -h "$ISO_FILE" | cut -f1))"
curl -sf -T "$ISO_FILE" "$FARM_HTTP/$(basename "$ISO_FILE")" || fail "ISO upload"
curl -sf -T "$ISO_FILE.sha256" "$FARM_HTTP/$(basename "$ISO_FILE").sha256" || fail "sha upload"
curl -sf -T "$LOG" "$FARM_HTTP/build.log" || true

echo "==> build complete, powering off"
systemctl poweroff
