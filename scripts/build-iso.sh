#!/usr/bin/env bash
# Build the FarmNerdOS ISO.
# Merges the stock archiso 'releng' profile with our overlay in iso/,
# swaps the kernel to linux-cachyos, then runs mkarchiso.
# Run as root on an Arch host with 'archiso' installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELENG="/usr/share/archiso/configs/releng"
WORK="$ROOT/work"
PROFILE="$WORK/profile"
OUT="$ROOT/out"
REPO_DIR="$ROOT/repo/x86_64"
CACHY_KEY="F3B607488DB35A47"

[[ $EUID -eq 0 ]]   || { echo "error: must run as root (mkarchiso needs it)"; exit 1; }
[[ -d $RELENG ]]    || { echo "error: archiso not installed (pacman -S archiso)"; exit 1; }
[[ -f $REPO_DIR/farmnerdos.db.tar.gz ]] || {
    echo "error: local [farmnerdos] repo missing — run scripts/build-packages.sh first"; exit 1; }

# --- trust the CachyOS signing key on the build host -------------------------
if ! pacman-key --list-keys "$CACHY_KEY" &>/dev/null; then
    echo "==> importing CachyOS signing key"
    pacman-key --recv-keys "$CACHY_KEY" --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key "$CACHY_KEY"
fi

# --- assemble profile: releng base + FarmNerdOS overlay ----------------------
echo "==> assembling profile"
rm -rf "$WORK"
mkdir -p "$PROFILE" "$OUT"
cp -a "$RELENG/." "$PROFILE/"
cp -a "$ROOT/iso/." "$PROFILE/"

# point build-time pacman.conf at the local package repo
sed -i "s|@FARMNERDOS_REPO@|file://$REPO_DIR|" "$PROFILE/pacman.conf"

# --- swap kernel: linux -> linux-cachyos -------------------------------------
echo "==> switching boot configs to linux-cachyos"
# releng ships a mkinitcpio preset named for the stock kernel
if [[ -f "$PROFILE/airootfs/etc/mkinitcpio.d/linux.preset" ]]; then
    sed 's/vmlinuz-linux/vmlinuz-linux-cachyos/g;
         s/initramfs-linux/initramfs-linux-cachyos/g' \
        "$PROFILE/airootfs/etc/mkinitcpio.d/linux.preset" \
        > "$PROFILE/airootfs/etc/mkinitcpio.d/linux-cachyos.preset"
    rm "$PROFILE/airootfs/etc/mkinitcpio.d/linux.preset"
fi
# bootloader entries (systemd-boot, syslinux, grub).
# NB: grep in a pipeline + pipefail would abort on zero matches; collect first.
mapfile -t boot_cfgs < <(grep -rlE 'vmlinuz-linux|initramfs-linux' \
    "$PROFILE/efiboot" "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null || true)
(( ${#boot_cfgs[@]} > 0 )) || { echo "error: no bootloader configs found to patch — releng layout changed?"; exit 1; }
for f in "${boot_cfgs[@]}"; do
    sed -i 's/vmlinuz-linux/vmlinuz-linux-cachyos/g;
            s/initramfs-linux/initramfs-linux-cachyos/g' "$f"
done
# verify nothing still points at the stock kernel
if grep -rqE 'vmlinuz-linux(\.|$| )' "$PROFILE/efiboot" "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null; then
    echo "error: stock kernel references remain after patching"; exit 1
fi

# --- drop releng leftovers that don't fit a KDE live session ------------------
echo "==> pruning releng console-live leftovers"
rm -f "$PROFILE/airootfs/usr/local/bin/choose-mirror" \
      "$PROFILE/airootfs/usr/local/bin/livecd-sound" \
      "$PROFILE/airootfs/usr/local/bin/Installation_guide" \
      "$PROFILE/airootfs/root/.automated_script.sh" \
      "$PROFILE/airootfs/root/.zlogin"

# --- stash kernel+ucode packages inside the ISO --------------------------------
# mkarchiso strips /boot from the squashfs, so the installed system has no
# kernel file. Calamares' cleanup module reinstalls these in the target
# (offline), which also regenerates a proper default mkinitcpio preset.
echo "==> stashing kernel packages for the installer"
PKGSTASH="$PROFILE/airootfs/usr/share/farmnerdos/pkgs"
mkdir -p "$PKGSTASH"
pacman -Syw --noconfirm --config "$PROFILE/pacman.conf" \
    --cachedir "$PKGSTASH" linux-cachyos amd-ucode intel-ucode
# drop detached sigs: the target verifies local files only when a .sig is
# present, and the keyring may not exist yet at that point
rm -f "$PKGSTASH"/*.sig

# --- live-session services ----------------------------------------------------
echo "==> enabling live services"
SYSD="$PROFILE/airootfs/etc/systemd/system"
mkdir -p "$SYSD/multi-user.target.wants" "$SYSD/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$SYSD/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/sddm.service "$SYSD/display-manager.service"
# releng enables services for its console live env that we drop or replace:
# iwd/networkd (NM replaces), cloud-init/iscsi (packages not shipped — would be
# dangling symlinks), sshd (no reason to expose a live box), choose-mirror.
rm -f "$SYSD/multi-user.target.wants/iwd.service" \
      "$SYSD/multi-user.target.wants/systemd-networkd.service" \
      "$SYSD/network-online.target.wants/systemd-networkd-wait-online.service" \
      "$SYSD/sockets.target.wants/systemd-networkd.socket" \
      "$SYSD/multi-user.target.wants/sshd.service" \
      "$SYSD/multi-user.target.wants/iscsid.service" \
      "$SYSD/multi-user.target.wants/choose-mirror.service" \
      "$SYSD/choose-mirror.service" \
      "$SYSD/etc-pacman.d-gnupg.mount" 2>/dev/null || true
rm -rf "$SYSD/cloud-init.target.wants" 2>/dev/null || true

# releng autologs root on tty1 — drop that, SDDM owns the session now
rm -rf "$SYSD/getty@tty1.service.d" 2>/dev/null || true

# --- build --------------------------------------------------------------------
echo "==> running mkarchiso"
mkarchiso -v -w "$WORK/archiso-tmp" -o "$OUT" "$PROFILE"

echo "==> done:"
ls -lh "$OUT"/*.iso
